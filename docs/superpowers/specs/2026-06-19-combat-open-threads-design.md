# Combat Open Threads — Design Spec

> **Date:** 2026-06-19
> **Status:** Approved design, pre-plan. Source of truth for design = `DESIGN.md`; this spec
> translates four `DESIGN.md` threads into concrete combat architecture. If this and `DESIGN.md`
> disagree, `DESIGN.md` wins — flag it.
> **Naming:** follows the LOCKED convention in `CLAUDE.md §2` (classes PascalCase, files
> snake_case, signals snake_case past-tense, handlers `_on_<emitter>_<signal>`).
> **Balance:** every concrete number is an `[ASSUMPTION]` placeholder — tuned by playtest after the
> spin is fun (CLAUDE.md §5 hard ceiling: the human judges feel, not Claude).

---

## 1. Goal

Close the four open threads from the vertical-slice combat prototype, in dependency order, each
test-first with a review checkpoint between waves:

| Wave | Feature | Depends on | Player-facing payoff |
|------|---------|-----------|----------------------|
| **A** | `Effect` system + **Crushing → Slow** | — | Slow status pip; turn order visibly re-sorts |
| **B** | `ResourcePool` (Stamina only) | — | Stamina bar on the combatant panel |
| **C** | **Main-Phase reel splice** (+1 Storm reel) | B | Main-1 "Splice Storm reel" button |
| **D** | **Sticky-Wild Ultimate** | existing `BonusMeter` | Main-1 "Fire Ultimate" button + glowing WILD reel |

B and C are a matched pair — Stamina exists *to gate* reel-splicing, so the resource bar has a job.
A and D are independent and could swap order, but the table order is the recommended build sequence.

This proves three things the prototype does not yet exercise: **turn-order manipulation** (A),
**spend-to-edit-your-reels in combat** (B+C, the core "builds edit the reels" hook expressed
*live*), and the **Ultimate as class identity** (D).

---

## 2. Shared structural change — the interactive Main Phase 1

This is the single biggest change and underpins waves C and D. Today Main 1 is pass-through; the
player only acts at SPIN and END TURN. Reel-splicing and Ultimate-firing are **Main-1 planning
decisions** (`DESIGN.md §4.8`), so Main 1 must become a pause point the player acts in.

### 2.1 `PhaseManager` (revised contract)

`combat/phase_manager.gd` — splits the single pause into two:

- `start_turn()` → enters **Upkeep**, then **Main 1**, then **pauses** (no longer auto-advances to
  Combat). Emits `phase_changed` per phase as today.
- `proceed_to_combat()` → **new.** Enters **Combat**, then pauses for the spin.
- `resume_after_combat()` → **unchanged.** Main 2 → End → `turn_finished`.

`PhaseManager` stays a **pure phase sequencer** — it holds no combatant/game state. It only emits
`phase_changed(phase)` and `turn_finished`.

### 2.2 Upkeep / End bookkeeping lives on `Combatant` (testable)

Per-turn bookkeeping is exposed as direct methods on `Combatant` so it is unit-testable without the
scene:

- `on_upkeep()` — regen the `ResourcePool` (+stamina), tick start-of-turn `Effect`s, recompute
  `current_initiative`.
- `on_end()` — tick end-of-turn `Effect`s (for the prototype, Slow ticks here; see §3.4),
  recompute `current_initiative`. (The sticky-wild counter is decremented at **spin time**, not
  here — see §6.1.)

The orchestrator (`Combat`) calls these off `phase_changed` (UPKEEP → `on_upkeep`, END →
`on_end`). This keeps `PhaseManager` pure while keeping the logic out of the view.

> **Decision — where Slow ticks:** Slow duration is measured in **the bearer's own turns** and
> ticks down at the bearer's **End** phase. `[ASSUMPTION]` duration 2 = the bearer's next two turns
> are slowed. This is the most legible reading for the pip countdown (`SLOW 2 → 1 → off`) and avoids
> ambiguity about "rounds" when combatant counts vary.

### 2.3 `Combat` orchestrator (revised flow)

- The SPIN button is **reframed as "commit Main 1 and spin"**: while paused in Main 1 the player may
  use Main-1 actions (splice, fire ultimate); pressing SPIN calls `proceed_to_combat()` then runs
  the existing `_do_spin`. The enemy auto-commits after `ENEMY_THINK_DELAY` (it takes no Main-1
  actions in the prototype).
- A new **`_turn_reels: Array[ActionReel]`** holds the reel set actually spun this turn. It starts
  as a copy of `attacker.weapon.reels` at turn start and may be appended to in Main 1 (wave C). The
  spin resolves `_turn_reels`, not `weapon.reels` directly.

### 2.4 `Combatant` new live-state fields

`combat/combatant.gd` gains:

- `base_initiative: int` — the raw rolled value (set by `TurnManager.roll_initiative`).
- `current_initiative` becomes **derived**: `base_initiative + Σ active INITIATIVE_MOD magnitudes`,
  recomputed by `recompute_initiative()`. We no longer mutate-and-unmutate the sort key, which
  removes a class of "forgot to reverse the modifier" bugs. `TurnManager` still sorts by
  `current_initiative` unchanged.
- `active_effects: Array[Effect]`
- `resource_pool: ResourcePool`
- sticky-wild tracking (see §6).

---

## 3. Wave A — `Effect` system + Crushing → Slow

### 3.1 `Effect` resource

`combat/resources/effect.gd` (extends Resource) — matches the `ARCHITECTURE.md §7` stub:

```
enum Kind { INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT, REEL_FACE_EDIT }
@export var id: StringName = &""
@export var kind: Kind = Kind.INITIATIVE_MOD
@export var magnitude: float = 0.0
@export var duration: int = 1          # bearer's turns remaining; ticks down in on_end()
```

Only `INITIATIVE_MOD` is exercised this wave. `is_expired() -> bool` returns `duration <= 0`.
`tick()` decrements `duration`.

> **Duplicate-on-attach:** `Effect` is a `Resource` (shared by reference). The library returns a
> `duplicate()` so each combatant owns its own live countdown — attaching the same definition to two
> combatants must not share a duration counter.

### 3.2 `EffectLibrary`

`combat/effect_library.gd` — resolves a `StringName` id (from `DamageType.inherent_rider_id` or
`ReelFace.rider_effect_id`) into a fresh `Effect` instance. For the prototype it is a small static
registry holding the one rider we need: `&"slow"` → INITIATIVE_MOD, magnitude `-20`, duration `2`.
`[ASSUMPTION]` values. (Authorable as `.tres` later; a code registry is fine for one rider — YAGNI.)

### 3.3 Resolution path (honors the authority rule)

`ARCHITECTURE.md §2`: `CombatResolver` computes, `Combat` applies. Riders follow the same split:

1. `CombatResolver._resolve_single` already lands a face. When the face is **crit-success AND deals
   damage** and the reel's `damage_type.inherent_rider_id` is non-empty, the resolver records that
   id on the `AttackResult` (new field `rider_effect_id: StringName`). The resolver does **not**
   attach anything.
2. `Combat._apply_attack` reads `attack.rider_effect_id`; if set, it asks `EffectLibrary` for a
   fresh `Effect` and attaches it to the **defender** (`defender.attach_effect(effect)`), which
   calls `recompute_initiative()`.

> **Trigger = crit-success only.** 1 crit-success face / 10 per reel → across the enemy's 2 reels,
> Slow lands roughly 1 turn in 5: an *event*, not a passive. Tying it to success-too would fire
> ~50% of turns and churn the turn order every round, violating the legibility pillar. No separate
> proc roll — the reel IS the dice.

### 3.4 Turn-order re-sort & legibility

- Effects change `current_initiative` immediately, but **turn order re-sorts at the next round
  start** (`TurnManager._start_next_round` already recaptures `_order` via `get_turn_order()`).
  Mid-round order stays fixed — the standard, legible behavior. The player watches the
  turn-order bar reshuffle when the new round opens.
- `TurnOrderBar` / `CombatantPanel` show a **`SLOW −20 (n)` pip** on the slowed combatant that
  counts down (`2 → 1 → off`) so the player connects "rat crit on its Crushing reel" → "I slid down
  the order." This is the wave's whole point — surface the *why*.

### 3.5 Prototype framing

First demo = **enemy Crushing Slows the PC** (the scenario already has a Crushing-weapon enemy vs.
the Slashing PC). Losing initiative is a threat the player *feels*, and it stress-tests the re-sort
path. The PC gets **no** Crushing option this wave (YAGNI) — the PC-side turn-order play arrives
later via splicing (wave C is Storm coverage, not Crushing; a PC Crushing reel is future work).

### 3.6 Wave A tests (test-first)

- `tests/test_effect.gd` — attach/tick/expire; `recompute_initiative` reflects active mods;
  duplicate-on-attach does not share duration.
- `tests/test_crushing_slow.gd` — through the real `CombatResolver` + `TurnManager`: a forced
  crit-success on a Crushing reel attaches Slow to the defender, `current_initiative` drops by 20,
  and `get_turn_order()` reflects the new order; the pip expires after 2 bearer-turns.

---

## 4. Wave B — `ResourcePool` (Stamina only)

`combat/resource_pool.gd` (extends RefCounted) — matches the `ARCHITECTURE.md §7` stub but the
prototype uses **Stamina only**; Focus/Mana stay unbuilt (a 1v1 duelist is physical; three bars is
bookkeeping bloat with no new decisions — §7 YAGNI).

```
var stamina: int
var max_stamina: int
signal pool_changed(kind: StringName, value: int, max: int)
func can_afford(cost: Dictionary) -> bool
func spend(cost: Dictionary) -> bool      # returns false (no-op) if unaffordable
func regen() -> void                       # +regen_per_turn, clamped to max
```

`cost` is a `Dictionary` keyed by resource (`{&"stamina": 2}`) so Focus/Mana slot in later without
signature changes. **Partial regen** is what makes spending a trade-off — a full refill would make
spending free.

`[ASSUMPTION]` values: start **3**, max **5**, regen **+1 per round** (applied in `on_upkeep`).
Shown on `CombatantPanel` as a small Stamina bar/number.

### 4.1 Wave B tests

- `tests/test_resource_pool.gd` — `can_afford` true/false at boundaries; `spend` deducts and
  refuses when short (returns false, no mutation); `regen` adds and clamps at max; `pool_changed`
  fires on change only.

---

## 5. Wave C — Main-Phase reel splice (+1 typed reel)

The single most pillar-proving in-combat editor: **splice one extra Storm reel for this turn** at a
Stamina cost. It changes reel **count** *and* **typing** at once — the multi-typing path
`DESIGN.md §4.6`/`§4.8` calls out — and it makes the type chart bite: Cluny's Rat defends as Earth,
so a Storm reel is real coverage the Slashing weapon can't express.

### 5.1 Mechanic

- Main-1 button **"Splice Storm reel (2 STA)"**, enabled only when affordable and `_turn_reels.size()
  < 5` (the band ceiling). On press: `resource_pool.spend({&"stamina": 2})`, then append one
  `ActionReel.make_default(storm)` (base damage taken from the weapon, 10) to `_turn_reels`.
- **Additive, this turn only:** 3 → 4 reels; `_turn_reels` is rebuilt from `weapon.reels` each turn,
  so the splice never persists. Never overwrites the weapon's native reels (matches the locked
  additive rule).
- **Legibility:** the spliced reel appears in the loadout strip in a **distinct type color** *before*
  the spin, so the player sees the loadout grow from 3 to 4 and knows why the 4th reel is a
  different color when it scrolls.

### 5.2 Trade-off (keeps it from strictly-best)

- Costs 2 Stamina → a weaker next turn (the §4 trade-off pillar, made legible by one bar).
- Off-type **coverage, not raw power** — great into Earth, mediocre into Storm-resistant defenders;
  against a Slashing-weak target the player should prefer native reels. Context-dependent by design.

`[ASSUMPTION]` values: cost **2 STA**, **+1** Storm reel at base damage **10**, default tier
composition, this turn only, capped at the 5-reel band.

### 5.3 Wave C tests

- `tests/test_reel_splice.gd` — splicing appends exactly one Storm-typed reel; costs 2 Stamina;
  refused (no append, no spend) when unaffordable; refused at the 5-reel cap; `_turn_reels` resets
  to `weapon.reels` size on the next turn.

---

## 6. Wave D — Sticky-Wild Ultimate

`combat/ultimate.gd` (extends RefCounted) — matches the `ARCHITECTURE.md §7` stub; the prototype
implements **`STICKY_WILD`** only (the duelist's identity per `DESIGN.md §4.9`, and the thinnest
layer over what's already test-green).

### 6.1 Mechanic (in existing reel/spin terms)

- The `BonusMeter` already arms at cap and exposes `is_armed()` / `consume()`.
- **Main-1 action "Fire Ultimate"** — enabled only when `bonus_meter.is_armed()`. On fire:
  `bonus_meter.consume()` (cost = the full meter only, never the ResourcePool — `§4.9`), and set
  sticky-wild state on the combatant.
- **Sticky wild:** designate **one reel** (auto = reel index 0 for the prototype; reel-pick UI is a
  later polish — auto-target keeps the demo focused and is fully legible since that reel glows). For
  the next **2 spins**, that reel is **guaranteed to land on its existing crit-success face**
  (×2.0). Reuses the faces already on the strip; the strip simply lands on the crit-success index,
  so it animates cleanly. The reel shows a **glowing WILD** marker before the spin.
- Implemented as a per-reel override `CombatResolver` honors: `resolve_combat_phase` takes an
  optional `wild_reel_indices: Array[int]` (or a per-reel flag); a wild reel returns its
  crit-success face instead of a random `spin()`. Damage still routes through the type chart and the
  multiplier — the Ultimate **improves a reel's outcome floor**, it does not bypass the chart.
- Combatant tracks `sticky_wild_reel: int` (−1 = none) and `sticky_wild_spins_remaining: int`,
  decremented each Combat phase it applies; reverts to normal at 0.

> **Why auto-target reel 0:** proves the duelist's "consistent pressure" identity (a guaranteed
> strong independent attack) without adding reel-selection UI that would compete with the Slow and
> splice demos for the player's attention. Reel-pick is a clean, isolated follow-up.

### 6.2 Trade-off

Firing dumps the whole bar (no partial spend) and buffs only one reel — so *when* to fire (punch
through the Earth-defending rat, or push lethal) is the decision; banking the meter toward a turn
where the guaranteed crit lands lethal is often correct.

`[ASSUMPTION]` values: meter cost = full **10**, sticky duration **2 spins** (this turn's Combat +
next turn's), auto reel **0**, wild resolves as the existing crit-success face (×2.0).

### 6.3 Wave D tests

- `tests/test_ultimate_sticky_wild.gd` — fire requires `is_armed()`; firing consumes the meter to 0;
  the designated reel forces crit-success for exactly 2 spins, then reverts to random; firing does
  **not** touch the ResourcePool; `CombatResolver` honors the wild override and still applies the
  type chart.

---

## 7. Test & verification summary

All four waves have pure-logic cores written **test-first** (red → green), run headless:

```
Godot_v4.6.3-stable_win64 --headless --path bunnies --script res://tests/test_<name>.gd
# after adding a NEW class_name, refresh the class cache first:
Godot_v4.6.3-stable_win64 --headless --path bunnies --editor --quit
```

New suites: `test_effect`, `test_crushing_slow`, `test_resource_pool`, `test_reel_splice`,
`test_ultimate_sticky_wild`. Updated suites: `test_phase_manager` (new Main-1 pause contract),
`test_combat_loop` (integration through the revised flow). All must stay green before a wave's
review checkpoint.

**Machine-verifiable:** all logic + integration is test-green and `combat.tscn` loads without
errors. **Human call (CLAUDE.md §5 ceiling):** whether the Slow swing, the splice decision, the
Ultimate fire, and the resource squeeze *feel* good — play `combat.tscn` and judge.

---

## 8. All `[ASSUMPTION]` numbers in one place

Kept as easily-editable data, not hard-coded constants where avoidable (CLAUDE.md §4):

| Knob | Value | Where |
|------|-------|-------|
| Slow Initiative penalty | −20 | `EffectLibrary` slow def |
| Slow duration | 2 bearer-turns | `EffectLibrary` slow def |
| Stamina start / max | 3 / 5 | `ResourcePool` config |
| Stamina regen | +1 / round | `ResourcePool.regen` |
| Reel-splice cost | 2 Stamina | splice action |
| Spliced reel | +1 Storm, base 10, default comp, this turn | splice action |
| Reel band ceiling | 5 | splice cap |
| Ultimate meter cost | full meter (10) | `BonusMeter.consume` |
| Sticky-wild duration | 2 spins | sticky-wild state |
| Sticky-wild target | reel 0 (auto) | sticky-wild state |

---

## 9. Out of scope (do not build this pass — YAGNI / post-1.0)

- Focus/Mana resources, the rest of the `Effect.Kind` menu (DoT, multiplier-edit, reel-face-edit),
  and the other five Ultimate archetypes.
- Reel-selection UI for the Ultimate (auto reel 0 this pass).
- PC Crushing weapon / a PC-side Slow.
- Enemy Main-1 AI (the enemy takes no Main-1 actions in the prototype).
- Any roguelite system, `Class`/`EncounterTable`/`RewardTable`/talents (`DESIGN.md §8` deferred).
