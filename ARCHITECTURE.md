# ARCHITECTURE.md — Bunnies combat architecture

> **Status:** Living reference for the **as-built** combat system (vertical-slice prototype) plus
> concrete stub contracts for the next combat classes. **`DESIGN.md` is the source of truth for
> the design; this doc describes the code.** If they disagree, `DESIGN.md` wins — flag it.
> Naming convention is LOCKED in `CLAUDE.md §2` (classes PascalCase, files snake_case, signals
> snake_case **past-tense** like `spin_resolved`; handlers `_on_<emitter>_<signal>`).
>
> **Scope of this doc:** the combat system as it exists today — including the now-built combat
> threads (`Effect`/Crushing→Slow, `ResourcePool`, Main-Phase reel splice, the STICKY_WILD
> `Ultimate`). World/meta classes (`Class`, `EncounterTable`, `RewardTable`, talents) remain a
> `DESIGN.md §8` sketch — not yet designed in code.

---

## 1. Folder map

```
res://                                  (git root = C:\Bunnies\bunnies-main\bunnies\)
  project.godot                         main_scene = res://combat/combat.tscn
  combat/
    resources/        DATA (Resource, inspector-editable)
      reel_face.gd        ReelFace
      reel.gd             Reel            (abstract base)
      initiative_reel.gd  InitiativeReel  (extends Reel)
      action_reel.gd      ActionReel      (extends Reel)
      damage_type.gd      DamageType
      weapon.gd           Weapon
      effect.gd           Effect          (buffs/debuffs/riders)
      types/              slashing.tres · piercing.tres · crushing.tres ·
                          storm.tres · mystic.tres · earth.tres   (the 6-type chart, [ASSUMPTION] values)
    combat_resolver.gd    CombatResolver  (pure calculator)
    combatant.gd          Combatant
    effect_library.gd     EffectLibrary   (rider factory)
    resource_pool.gd      ResourcePool    (Stamina, prototype)
    bonus_meter.gd        BonusMeter
    turn_manager.gd       TurnManager
    phase_manager.gd      PhaseManager
    combat.gd / combat.tscn   Combat      (orchestrator + main scene)
    ui/
      reel_strip.gd       ReelStrip       (scrolling Action-reel view)
      combatant_panel.gd  CombatantPanel  (name + HP + Bonus Meter)
      turn_order_bar.gd   TurnOrderBar
  tests/                  headless SceneTree test scripts (see §6)
```

Design docs (`DESIGN.md`, `CLAUDE.md`, `HANDOFF.md`, this file) live one level up in
`C:\Bunnies\bunnies-main\` — outside the git repo, alongside each other.

---

## 2. The authority rule (read this first)

**`CombatResolver` computes the result; nothing else does.** It spins the reels and returns, for
each reel, an `AttackResult` carrying `final_damage` and `meter_gain`. It does **not** mutate any
combatant.

**`Combat` (the orchestrator) applies results**: it tells each `ReelStrip` to animate *to* the
already-decided face, and as each strip settles it calls `Combatant.take_damage()` and
`BonusMeter.charge()`. The scrolling animation is cosmetic — it never decides an outcome.

This split is why the logic is fully unit-testable headless while the feel lives in the scene.

### Data flow of one turn
```
TurnManager.turn_started(combatant)
  └─ Combat._on_turn_started
       ├─ PhaseManager.start_turn()  → Upkeep → Main 1 → Combat (pause)
       ├─ build ReelStrips for attacker.weapon.reels
       └─ player: enable SPIN  │  enemy: auto-spin after a delay
            └─ Combat._do_spin
                 ├─ CombatResolver.resolve_combat_phase(reels, base_damage, defender.defense_type)
                 │     → Array[AttackResult]   (results decided HERE)
                 └─ per reel: ReelStrip.play_to(face_index, staggered)
                      └─ strip_settled → Combat._apply_attack(result)
                           ├─ defender.take_damage(result.final_damage)   → hp_changed / defeated
                           └─ attacker.bonus_meter.charge(result.face.result_tier) → meter_changed / meter_armed
            └─ all settled → Combat._finish_spin
                 ├─ combat over?  → PhaseManager.resume_after_combat → turn_finished → TurnManager.advance_turn → combat_ended → result overlay
                 ├─ player?       → enable END TURN, wait → resume_after_combat → … → advance_turn
                 └─ enemy?        → resume_after_combat → … → advance_turn
```

---

## 3. Data resources (implemented)

All `Resource`-based so they're inspector-editable (CLAUDE.md §2).

### `ReelFace` — `combat/resources/reel_face.gd` (extends Resource)
One face on a reel. Single type serves both reel kinds (nullable fields, per DESIGN §8).
- `enum ResultTier { CRIT_FAILURE, FAILURE, NEUTRAL, SUCCESS, CRIT_SUCCESS }`
- `result_tier: ResultTier`, `multiplier: float`, `rider_effect_id: StringName` — Action faces
- `digit: int` (−1 when unused) — Initiative faces
- `deals_damage() -> bool` — true only for SUCCESS / CRIT_SUCCESS

### `Reel` — `combat/resources/reel.gd` (extends Resource, abstract base)
- `faces: Array[ReelFace]`, `weights: Array[float]` (empty = uniform)
- **signals:** `spin_started`, `face_resolved(face: ReelFace)`
- `spin() -> ReelFace` — emits the signals; weighted if `weights` is valid, else uniform
- Do not instantiate directly — use a subclass:

**`InitiativeReel`** (extends Reel) — digit 0–9 reel; a **constant shared by all combatants**.
- `static make_default() -> InitiativeReel` — builds the 0–9 strip
- `static roll_percentile(tens, ones) -> int` — 2-reel d100, **00 reads as 100**, range 1–100

**`ActionReel`** (extends Reel) — result-tier reel; **varies by build**.
- `damage_type: DamageType`
- `static make_default(type = null) -> ActionReel` — physical **10-face strip**
  (`DEFAULT_COMPOSITION`: 1 crit-fail · 2 fail · 2 neutral · 4 success · 1 crit-success →
  crits 10% each). Odds come from symbol counts, not hidden weights. `[ASSUMPTION]` balance.

### `DamageType` — `combat/resources/damage_type.gd` (extends Resource)
The type chart, one row per type (DESIGN §5). Replaces the old PayTable.
- `enum Type { SLASHING, PIERCING, CRUSHING, STORM, MYSTIC, EARTH }`
- `type: Type`, `inherent_rider_id: StringName`, `effectiveness: Dictionary` (defender Type→mult),
  `default_multiplier: float`
- `multiplier_against(defender: DamageType) -> float`
- The 6 `.tres` in `resources/types/` hold gentle placeholder values (`[ASSUMPTION]`; real 6×6 is a
  DESIGN §5.1 deliverable).

### `Weapon` — `combat/resources/weapon.gd` (extends Resource)
- `base_damage: float`, `reels: Array[ActionReel]` (the 2–5 baseline band)

### `Effect` — `combat/resources/effect.gd` (extends Resource) — buffs/debuffs/riders (DESIGN §11 A4, §4.1)
Reel faces APPLY effects (via `rider_effect_id`); they don't contain them.
- `enum Kind { INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT, REEL_FACE_EDIT }`
- `id: StringName`, `kind: Kind`, `magnitude: float`, `duration: int`
- `tick()` (decrement duration), `is_expired() -> bool`

### `EffectLibrary` — `combat/effect_library.gd` — rider factory
- `make(id) -> Effect` — returns a **fresh duplicate** of the named effect
- Holds the `&"slow"` rider = `INITIATIVE_MOD`, magnitude −20, duration 2 (`[ASSUMPTION]`) — the
  Crushing→Slow target rider.

### `ResourcePool` — `combat/resource_pool.gd` (extends RefCounted) — DESIGN §10 Dec 6
Spent in Main 1; FULLY INDEPENDENT of `BonusMeter`. Stamina only for the prototype.
- `stamina`, `max_stamina`, `regen_per_turn`
- **signal:** `pool_changed`
- `can_afford(cost) -> bool`, `spend(cost) -> bool`, `regen()` — `cost` is a `Dictionary` keyed by
  `&"stamina"`

---

## 4. Combat logic (implemented)

### `CombatResolver` — `combat/combat_resolver.gd` (extends Node) — pure calculator
- nested `class AttackResult { face, damage_type, base_damage, final_damage:int, meter_gain:int, rider_effect_id }`
  — `rider_effect_id` is the rider the resolver **reports** on a crit-success of a riding type; the
  orchestrator applies it (authority rule §2).
- `@export meter_charge_weights: Array[int] = [0,0,1,2,3]` (`[ASSUMPTION]`)
- `resolve_combat_phase(reels: Array[ActionReel], base_damage: float, target_type: DamageType = null, wild_reel_indices: Array[int] = []) -> Array[AttackResult]`
  — each reel resolves **independently**; damage = `base × face.multiplier × type_chart`, rounded;
  non-damaging tiers deal 0. A reel whose index is in `wild_reel_indices` is **overridden** to its
  crit-success face (`_crit_face`, with a `spin()` fallback) — the Sticky-Wild Ultimate hook. Emits
  `spin_started`, `damage_applied(attack)` per reel, `meter_charged(total)`, `spin_resolved(attacks)`.
  (The orchestrator may use the return value and apply effects itself — see §2.)

### `Combatant` — `combat/combatant.gd` (extends RefCounted)
- config: `display_name`, `is_player`, `max_hp`, `weapon`, `defense_type: DamageType`, `bonus_meter`,
  `resource_pool: ResourcePool` (Stamina, prototype-seeded 3/5 +1/round for the player)
- live: `hp`, `base_initiative`, `current_initiative` — the turn-order sort key, now **derived** via
  `recompute_initiative()` (`base_initiative` + active `INITIATIVE_MOD` magnitudes); `active_effects: Array[Effect]`
- live (per turn): `turn_reels`, `sticky_wild_count`, `sticky_wild_spins_remaining`
- **signals:** `hp_changed(hp, max_hp)`, `defeated`
- `start_combat()` (seed hp), `take_damage(amount)` (clamps at 0, fires `defeated` once), `is_alive()`
- effects: `attach_effect()` (duplicates defensively), `tick_effects()`, `recompute_initiative()`,
  phase hooks `on_upkeep()` (regen pool, tick) / `on_end()`
- reel loadout: `begin_turn()` (copies `weapon.reels` into `turn_reels`),
  `try_splice_reel(type, base_damage, cost, cap)` (additive, spends Stamina, 5-reel cap)
- ultimate: `fire_sticky_wild(reel_count, spins)` (requires armed meter; consumes it — costs ONLY the
  meter; wilds the first `reel_count` reels = ALL weapon reels, splices excluded),
  `wild_reel_indices()` → `[0 … count-1]`, `consume_wild_spin()`

### `BonusMeter` — `combat/bonus_meter.gd` (extends RefCounted) — DESIGN §4.9
- `cap` (10), `floor` (per-class carryover), `charge_weights: Array[int]`, `is_visible`, `value`
- **signals:** `meter_changed(value, cap)`, `meter_armed`
- `charge(tier)`, `is_armed()`, `consume()`, `resolve_post_combat()` (below floor→0; floor≤v<cap→floor; full→carries)

### `TurnManager` — `combat/turn_manager.gd` (extends Node) — DESIGN §4.1, N-vs-M-safe
- `combatants: Array[Combatant]`, `round_number`
- **signals:** `initiative_rolled(combatant, value)`, `round_started(n)`, `turn_started(combatant)`, `combat_ended(winner_is_player)`
- `roll_initiative()`, `get_turn_order()` (desc by `current_initiative`), `is_combat_over()`,
  `winner_is_player()`, `begin()`, `advance_turn()` (orchestrator calls this once a turn fully resolves)

### `PhaseManager` — `combat/phase_manager.gd` (extends Node) — DESIGN §4.8
- `enum Phase { UPKEEP, MAIN_1, COMBAT, MAIN_2, END }`, `current_phase`
- **signals:** `phase_changed(phase)`, `turn_finished`
- `start_turn()` (runs Upkeep→Main 1, then **pauses** at Main 1 for resource-spend / reel-splice / Ultimate),
  `proceed_to_combat()` (enters Combat for the spin), `resume_after_combat()` (Main 2→End→`turn_finished`)

---

## 5. View + orchestrator (implemented)

Built procedurally in GDScript (no hand-authored `.tscn` for the components — `combat.tscn` is just
the root `Control` with `combat.gd`). View nodes bind to logic signals; they never own game state.

- **`ReelStrip`** (`ui/reel_strip.gd`, Control) — scrolls a column of tier-colored cells and snaps to
  a target index. `configure(reel)`, `play_to(target_index, delay)`, signal `strip_settled`.
  Tunables: `SPIN_DURATION` (1.15s), `REPEATS`, `VISIBLE_CELLS`.
- **`CombatantPanel`** (`ui/combatant_panel.gd`, Panel) — name + HP bar + Bonus Meter; `bind(combatant)`.
- **`TurnOrderBar`** (`ui/turn_order_bar.gd`, Panel) — `set_order(order)`, `set_current(combatant)`.
- **`Combat`** (`combat.gd`, Control) — builds the 1v1 scenario + UI, wires every signal, owns the
  **SPIN** / **END TURN** buttons and the scrollable combat log, runs the loop in §2, shows the
  victory/defeat overlay + restart. Tunables: `STRIP_STAGGER` (0.25s), `ENEMY_THINK_DELAY` (0.6s).

---

## 6. Headless test / verification workflow

No GUI judgment by Claude (CLAUDE.md §5 hard ceiling — the human judges "is the spin fun"). Pure
logic is covered by `SceneTree` test scripts in `tests/`:

```bash
# run one suite
Godot_v4.6.3-stable_win64 --headless --path bunnies --script res://tests/test_<name>.gd
# after adding a NEW class_name, refresh the class cache first or --script can't resolve it:
Godot_v4.6.3-stable_win64 --headless --path bunnies --editor --quit
```

Suites: `test_bonus_meter`, `test_combatant`, `test_turn_manager`, `test_phase_manager`,
`test_action_reel`, `test_effect`, `test_resource_pool`, `test_crushing_slow`, `test_reel_splice`,
`test_ultimate_sticky_wild`, and `test_combat_loop` (full integration through the real managers/resolver).
Each prints `… TEST PASSED/FAILED` and exits non-zero on failure. New combat logic is written
**test-first** (red → green). `gen_damage_types.gd` regenerates the 6 type `.tres`.

---

## 7. Combat threads — implemented

The near-term combat classes (DESIGN §8, §4.9, §10 Dec 6, §11 A4) are now **built and test-green**.
Their contracts live with their owners: `Effect` / `EffectLibrary` / `ResourcePool` in §3, the new
`Combatant` fields/methods and `PhaseManager` Main-1 pause in §4.

- **`Effect` + Crushing→Slow** (implemented) — `combat/resources/effect.gd` + `combat/effect_library.gd`.
  The resolver **reports** `rider_effect_id` on a crit-success of a riding type; the orchestrator
  attaches the `&"slow"` effect (`INITIATIVE_MOD` −20 / 2 turns) to the defender, whose
  `current_initiative` is re-derived via `recompute_initiative()` — demonstrating turn-order edits.
- **`ResourcePool`** (implemented) — `combat/resource_pool.gd`. Stamina only for the prototype;
  regenerated in `on_upkeep`, spent by reel-splice in Main 1, shown on `CombatantPanel`.
- **Main-Phase reel splice** (implemented) — Main 1 pauses; the player may
  `Combatant.try_splice_reel(...)` (additive, spends Stamina, 5-reel cap) before committing the spin.
- **`Ultimate` — STICKY_WILD only** (implemented) — wired directly on `Combatant`
  (`fire_sticky_wild` / `wild_reel_indices` / `consume_wild_spin`) + the resolver's
  `wild_reel_indices` override; costs ONLY the armed meter. The remaining five archetypes
  (`EXTRA_SPINS`, `CASCADE`, `MULTIPLIER_CASCADE`, `HOLD_RESPIN`, `PICKEM`) are **deferred**.

---

## 8. Deferred to DESIGN §8 (no code design yet)

`Class` (HP seed, reel/talent identity, `meter_floor`, `ultimate_archetype`), `EncounterTable`,
`RewardTable`, the talent system, and the world/hub structure. Post-prototype — see `DESIGN.md §8`,
§11, §12. Do not build speculatively (CLAUDE.md §7 YAGNI).

---

## 9. Future UI direction (recorded for later — NOT built yet)

Designer's UX vision for combat presentation, captured for a future UI cycle. The current prototype
uses placeholder Labels/bars and a **simple dice readout** for the STUNNED roll; the scrolling-reel
treatments below are the intended polish, deferred.

- **Scrolling reel-strip for the STUNNED d100 roll.** When a combatant resolves a stun-check, show
  the two digit reels (0–9 percentile) animating in the **same scrolling `ReelStrip` style as the
  attack reels**, in the action-reels area. (v1 uses a plain dice readout instead.)
- **Initiative roll as a scrolling reel-strip per character.** At combat start, each combatant's
  Initiative d100 should animate as a **small** scrolling reel-strip placed **beside that character's
  nameplate/panel** (next to HP, Bonus Meter, etc.), not as a single shared roll. This needs a
  compact, reusable digit reel-strip widget.
- **WoW-party-frame-style status UI.** Per-character frames showing active buffs/debuffs as **small
  icons/meters** (so the player reads combat state at a glance without text), with **hover-over
  tooltips** explaining each effect's impact. Replaces today's single text status line.
- **Shared need:** a reusable, size-configurable **digit/percentile reel-strip widget** (and a tier
  reel-strip already exists as `ReelStrip`) — both the STUNNED roll and the per-character Initiative
  roll consume it. Build that widget when this cycle is picked up.

These are player-facing polish; the underlying logic (initiative percentile, stun d100) already
exists as data and can drive these visuals when built. Do not build now (YAGNI).
