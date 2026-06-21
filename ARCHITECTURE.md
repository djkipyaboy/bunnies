# ARCHITECTURE.md — Bunnies combat architecture

> **Status:** Living reference for the **as-built** combat system (vertical-slice prototype) plus
> concrete stub contracts for the next combat classes. **`DESIGN.md` is the source of truth for
> the design; this doc describes the code.** If they disagree, `DESIGN.md` wins — flag it.
> Naming convention is LOCKED in `CLAUDE.md §2` (classes PascalCase, files snake_case, signals
> snake_case **past-tense** like `spin_resolved`; handlers `_on_<emitter>_<signal>`).
>
> **Scope of this doc:** the combat system as it exists today — including all now-built combat
> threads: `Effect`/Crushing→Slow, stacking debuffs (merge-by-id), `ResourcePool`, the staged
> Main Phase 1 (`MainPhasePlan`), the Main-Phase reel splice, the Sticky-Wild `Ultimate`
> (crit-bias redesign), paylines (`PaylineLibrary`/`PaylineResolver`), the `Stats`/`Gear` stat
> system + initiative tie-break, STUNNED, the reel-face shuffle, and the Luck stat. World/meta
> classes (`Class`, `EncounterTable`, `RewardTable`, talents) remain a `DESIGN.md §8` sketch —
> not yet designed in code.
>
> **Project status:** the combat prototype is code-complete + test-green (20 headless suites); work
> is **paused to design content** (races/classes/abilities/buffs-debuffs) before returning to
> implement that content and build full N-vs-M party combat. See `HANDOFF.md §6`.

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
      action_reel.gd      ActionReel      (extends Reel; faces shuffled at creation)
      damage_type.gd      DamageType
      weapon.gd           Weapon
      effect.gd           Effect          (buffs/debuffs/riders; stacking + polarity)
      stats.gd            Stats           (6 stats: Might/Finesse/Vigor/Focus/Grit/Luck)
      gear.gd             Gear            (equippable stat bonuses)
      types/              slashing.tres · piercing.tres · crushing.tres ·
                          storm.tres · mystic.tres · earth.tres   (the 6-type chart, [ASSUMPTION] values)
    combat_resolver.gd    CombatResolver  (pure calculator + grid builder)
    combatant.gd          Combatant
    effect_library.gd     EffectLibrary   (rider/buff factory: slow, inspirational)
    resource_pool.gd      ResourcePool    (Stamina, prototype)
    bonus_meter.gd        BonusMeter
    main_phase_plan.gd    MainPhasePlan   (staged Main-1 choices — preview, then commit on SPIN)
    payline_library.gd    PaylineLibrary  (line geometry generator)
    payline_resolver.gd   PaylineResolver (scores same-tier lines over the grid)
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
       ├─ attacker.begin_turn()  (turn_reels = copy of weapon.reels)
       ├─ PhaseManager.start_turn()  → Upkeep (attacker.on_upkeep) → Main 1 (pause; NOT auto → Combat)
       ├─ attacker.evaluate_stun(STUN_THRESHOLD)  → if STUNNED, SPIN rolls a d100 gate first (§11)
       ├─ build a fresh MainPhasePlan(attacker) — Main-1 toggles only PREVIEW (§8)
       ├─ build ReelStrips from plan.preview_reels()
       └─ player: enable SPIN (= commit Main 1 + spin)  │  enemy: auto-commit + spin after a delay
            └─ Combat._on_spin_pressed: plan.commit() → PhaseManager.proceed_to_combat() → _do_spin
                 ├─ CombatResolver.resolve_combat_phase(turn_reels, base_damage,
                 │       defender.defense_type, attacker.wild_reel_indices(),
                 │       weapon_reel_count, attacker.effective_stats().might)
                 │     → Array[AttackResult] + last_grid + paylines_resolved  (decided HERE)
                 └─ per reel: ReelStrip.play_to(result.landed_index, staggered)
                      └─ strip_settled → Combat._apply_attack(result)
                           ├─ defender.take_damage(result.final_damage)   → hp_changed / defeated
                           ├─ if result.rider_effect_id → defender.attach_effect(EffectLibrary.make(id))
                           └─ attacker.bonus_meter.charge(result.face.result_tier) → meter_changed / meter_armed
            └─ payline hits applied (crit→bonus dmg + Inspirational; success→+1 meter; neutral→refund STA)
            └─ all settled → Combat._finish_spin (attacker.consume_wild_spin())
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
  **The faces are `shuffle()`d at creation** — balance-neutral (same tier counts, only adjacency
  varies) so the spun pattern isn't a discoverable fixed sequence. Counting tier frequencies is
  therefore order-independent (the test asserts counts, not positions).

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
Reel faces / damage types APPLY effects (via `rider_effect_id` / `inherent_rider_id`); they don't
contain them. Supports **stacking with diminishing returns** and **polarity** for UI.
- `enum Kind { INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT, REEL_FACE_EDIT }` (only
  `INITIATIVE_MOD` is exercised today; the rest are reserved)
- `id: StringName`, `kind: Kind`, `magnitude: float`, `duration: int`
- `max_stacks: int = 1` (1 = non-stacking), `stack_magnitudes: Array[float]` (per-stack increment
  schedule; e.g. SLOW `[-20, -10, -5]`), `stacks: int = 1` (live count on an attached effect),
  `beneficial: bool` (true = buff/green, false = debuff/orange in the panel)
- `effective_magnitude() -> float` — sum of the first `stacks` entries of `stack_magnitudes` if set,
  else the flat `magnitude`. **This is the source of truth for stacking effects.**
- `add_stack() -> bool` — increments `stacks` up to `max_stacks` (false at the cap)
- `tick()` (decrement duration), `is_expired() -> bool` (duration ≤ 0)

### `EffectLibrary` — `combat/effect_library.gd` — rider/buff factory
- `make(id) -> Effect` — returns a **fresh duplicate** of the named effect (so each combatant owns
  its own live countdown). Registry holds:
  - `&"slow"` (debuff) = `INITIATIVE_MOD`, magnitude −20, duration 2, `max_stacks 3`,
    `stack_magnitudes [-20, -10, -5]` (cap −35) — the Crushing→Slow rider (`[ASSUMPTION]`).
  - `&"inspirational"` (buff) = `INITIATIVE_MOD`, magnitude +5, duration 2, `max_stacks 1`
    (refresh, don't stack) — the payline crit-line party buff (`[ASSUMPTION]`).

### `Stats` — `combat/resources/stats.gd` (extends Resource) — the six stats (2026-06-20 spec)
Flat direct modifiers (the value IS the bonus; the reel is the variance). `[ASSUMPTION]` range ~0–6.
- `@export might/finesse/vigor/focus/grit/luck: int = 0`
- `plus(other: Stats) -> Stats` — returns a new Stats with each field summed (null-safe), for
  `Combatant.effective_stats` (base + gear). Stat→lever map (all 1:1): **Might**→flat damage per
  hit, **Finesse**→initiative + tie-break, **Vigor**→max HP, **Focus**→max Stamina, **Grit**→meter
  floor, **Luck**→adds crit-success faces to weapon reels (`Combatant.apply_luck`).

### `Gear` — `combat/resources/gear.gd` (extends Resource) — equippable items (DESIGN A7)
- `display_name: String`, `enum Slot { WEAPON, ARMOR, TRINKET }`, `slot: Slot`, `stat_bonuses: Stats`
- Minimal — no recompute logic lives here; `Combatant.effective_stats` reads it. Prototype: Martin
  equips **"Padded Jerkin"** (ARMOR) granting Might 3 / Finesse 2 / Luck 2 (`[ASSUMPTION]`).

### `ResourcePool` — `combat/resource_pool.gd` (extends RefCounted) — DESIGN §10 Dec 6
Spent in Main 1; FULLY INDEPENDENT of `BonusMeter`. Stamina only for the prototype.
- `stamina`, `max_stamina`, `regen_per_turn`
- **signal:** `pool_changed`
- `can_afford(cost) -> bool`, `spend(cost) -> bool`, `regen()` — `cost` is a `Dictionary` keyed by
  `&"stamina"`

---

## 4. Combat logic (implemented)

### `CombatResolver` — `combat/combat_resolver.gd` (extends Node) — pure calculator + grid builder
- nested `class AttackResult { face, damage_type, base_damage, final_damage:int, meter_gain:int,
  rider_effect_id, landed_index:int }` — `rider_effect_id` is the rider the resolver **reports** on a
  crit-success of a riding type (the orchestrator applies it, authority rule §2); `landed_index` is
  the actual spun strip index, so the grid and the `ReelStrip` land on the *same* cell.
- `@export meter_charge_weights: Array[int] = [0,0,1,2,3]` (`[ASSUMPTION]`)
- `const WILD_CRIT_CHANCE: float = 0.65` — a Sticky-Wild reel lands its crit face with this
  probability (a **BIAS, not a force**); the other ~35% is a normal weighted spin, so wild grids
  vary. (`[ASSUMPTION]`.)
- `var last_grid: Array` — the most recent spin's 3-row × W-col weapon grid (`grid[col] = [top,
  center, bottom]` ReelFaces), built from each weapon reel's landed window (wrapping the strip).
- `resolve_combat_phase(reels, base_damage, target_type = null, wild_reel_indices = [], weapon_reel_count = -1, flat_damage_bonus = 0, extra_lines = []) -> Array[AttackResult]`
  — each reel resolves **independently**; `final_damage = ceili(base × face.multiplier × type_chart)
  + flat_damage_bonus` (round UP, project convention; `flat_damage_bonus` = attacker's Might);
  non-damaging tiers deal 0. A reel in `wild_reel_indices` lands its crit face with `WILD_CRIT_CHANCE`
  (the Ultimate hook). After the per-reel attacks it **builds the grid** from the first
  `weapon_reel_count` reels (−1 = all; splices are excluded by passing the weapon count) and
  **evaluates paylines** via `PaylineLibrary.lines_for(W)` + `extra_lines` (the reserved Luck hook).
  Emits `spin_started`, `damage_applied(attack)` per reel, `meter_charged(total)`,
  `spin_resolved(attacks)`, then `paylines_resolved(hits)`. The orchestrator applies effects, the
  payline rewards, and the flat-bonus authority split unchanged.

### `Combatant` — `combat/combatant.gd` (extends RefCounted)
- config: `display_name`, `is_player`, `max_hp`, `weapon`, `defense_type: DamageType`, `bonus_meter`,
  `resource_pool: ResourcePool` (Stamina, prototype-seeded 3/5 +1/round for the player),
  `base_stats: Stats`, `gear: Array[Gear]`, and pre-stat seeds `base_max_hp` / `base_max_stamina` /
  `base_meter_floor` (the live `max_hp` / pool max / meter floor are DERIVED from these + stats)
- live: `hp`, `base_initiative`, `current_initiative` — the turn-order sort key, **derived** via
  `recompute_initiative()` (`base_initiative` + active `INITIATIVE_MOD` `effective_magnitude()`s);
  `tiebreak_roll` (a stored d10 spin, the final tie-break); `active_effects: Array[Effect]`
- live (per turn): `turn_reels`, `sticky_wild_count`, `sticky_wild_spins_remaining`,
  `stunned_this_turn`, `stunned_last_turn` (the anti-lock memory)
- **signals:** `hp_changed(hp, max_hp)`, `defeated`
- `start_combat()` (seed hp), `take_damage(amount)` (clamps at 0, fires `defeated` once), `is_alive()`
- stats/gear: `effective_stats()` (base + each gear's `stat_bonuses`), `apply_stats()` (recompute
  `max_hp = base + vigor`, `pool.max_stamina = base + focus`, `meter.floor = base + grit` — call at
  setup after gear, before `start_combat`), `apply_luck()` (append `effective_stats().luck`
  crit-success faces to each weapon reel then reshuffle — call ONCE at setup, **not idempotent**)
- effects: `attach_effect()` — **merge-by-id**: a re-applied effect with an active `id` never makes a
  second instance; it `add_stack()`s (diminishing/capped, no-op for `max_stacks 1`) and refreshes
  `duration`; a new id is `duplicate()`d and appended. `tick_effects()`, `recompute_initiative()`,
  `_find_effect(id)`; phase hooks `on_upkeep()` (regen pool, recompute init) / `on_end()` (tick
  effects, carry the STUNNED flag forward)
- reel loadout: `begin_turn()` (copies `weapon.reels` into `turn_reels`),
  `try_splice_reel(type, base_damage, cost, cap)` (additive, spends Stamina, 5-reel cap)
- ultimate: `fire_sticky_wild(reel_count, spins)` (requires armed meter; consumes it — costs ONLY the
  meter; wilds the first `reel_count` reels = ALL weapon reels, splices excluded),
  `wild_reel_indices()` → `[0 … count-1]`, `consume_wild_spin()`
- stun: `evaluate_stun(threshold) -> bool` (STUNNED at turn start when `current_initiative <
  threshold` AND not immune; immune = STUNNED last turn — the anti-lock), static
  `stun_check_passed(roll) -> bool` (the d100 gate: 51+ recovers, 01–50 loses the turn)

### `BonusMeter` — `combat/bonus_meter.gd` (extends RefCounted) — DESIGN §4.9
- `cap` (class default **10**; the orchestrator sets the PC's to **15** for the Ultimate-cost
  redesign — `[ASSUMPTION]`), `floor` (per-class carryover, = `base_meter_floor + Grit`),
  `charge_weights: Array[int]`, `is_visible`, `value`
- **signals:** `meter_changed(value, cap)`, `meter_armed`
- `charge(tier)`, `add_flat(amount)` (a payline success-line +1), `is_armed()`, `consume()`,
  `resolve_post_combat()` (below floor→0; floor≤v<cap→floor; full→carries)

### `TurnManager` — `combat/turn_manager.gd` (extends Node) — DESIGN §4.1, N-vs-M-safe
- `combatants: Array[Combatant]`, `round_number`
- **signals:** `initiative_rolled(combatant, value)`, `round_started(n)`, `turn_started(combatant)`, `combat_ended(winner_is_player)`
- `roll_initiative()` — `base_initiative = InitiativeReel.roll_percentile(...) + effective_stats().finesse`,
  then `recompute_initiative()`; also stores each combatant's `tiebreak_roll` (a d10 spin)
- `get_turn_order()` — sort by `current_initiative` desc; **tie →** effective Finesse desc; **still
  tied →** the stored `tiebreak_roll` desc (a kept spin, not `randf`, so the order is stable as
  effects tick)
- `is_combat_over()`, `winner_is_player()`, `begin()`, `advance_turn()` (orchestrator calls this once
  a turn fully resolves)

### `PhaseManager` — `combat/phase_manager.gd` (extends Node) — DESIGN §4.8
- `enum Phase { UPKEEP, MAIN_1, COMBAT, MAIN_2, END }`, `current_phase`
- **signals:** `phase_changed(phase)`, `turn_finished`
- A **pure phase sequencer** — holds no combatant/game state.
- `start_turn()` (runs Upkeep→Main 1, then **pauses** at Main 1 for the staged plan — splice /
  Ultimate / stun gate; no longer auto-advances to Combat), `proceed_to_combat()` (enters Combat for
  the spin), `resume_after_combat()` (Main 2→End→`turn_finished`)

### `MainPhasePlan` — `combat/main_phase_plan.gd` (extends RefCounted) — 2026-06-19-main1-staging spec
The transient per-turn **stage-and-commit** plan for one combatant's Main 1. Built fresh each turn,
discarded at turn end. Splice / Fire-Ultimate are **toggles that mutate NOTHING** — they only update a
preview — until `commit()` runs on SPIN. This is the legibility fix (preview before committing) and
caps splice at 1/turn by construction.
- `_init(c, splice_type, splice_cost=2, reel_cap=5, wild_reel=0, wild_spins=2)`; state
  `splice_staged`, `fire_ultimate_staged`
- `can_stage_splice()` (affordable AND under the reel cap), `can_stage_ultimate()` (meter armed);
  `toggle_splice()` / `toggle_ultimate()` (un-stage always allowed; stage only if `can_stage_*`)
- **preview (pure, non-mutating):** `preview_reels()` (turn_reels + a staged splice reel),
  `preview_stamina()` (current − staged cost), `will_consume_meter()`, `effective_wild_indices()`
  (carryover wild ∪ a staged fire = ALL weapon reels, deduped/sorted)
- `commit()` — the single apply point: delegates to the committed `Combatant` methods
  (`try_splice_reel`, `fire_sticky_wild(weapon_reel_count, wild_spins)`); a no-op when nothing is
  staged. No inverse/refund logic is ever needed because staging mutates nothing.

### `PaylineLibrary` — `combat/payline_library.gd` (extends RefCounted) — 2026-06-20-paylines spec
- `static lines_for(width: int) -> Array` — generates the line set for a 3-row × W-col grid: one
  **column** per reel (length 3), one **row** per row (length = W), and length-3 **diagonals** over
  each 3-column window both ways (none when W<3). Line counts: 3×2 → 5, 3×3 → 8 (tic-tac-toe), 3×4 →
  11, 3×5 → 14. Returned as a flat `Array` of `Array[Vector2i]` cell lists so a future Luck build can
  simply **append extra lines** (the `extra_lines` resolver hook).

### `PaylineResolver` — `combat/payline_resolver.gd` (extends RefCounted) — 2026-06-20-paylines spec
- nested `class PaylineHit { cells: Array[Vector2i]; tier: ReelFace.ResultTier; length: int }`
- `static evaluate(grid, lines) -> Array[PaylineHit]` — for each line, a hit iff every cell shares one
  **scoring** tier (NEUTRAL / SUCCESS / CRIT_SUCCESS; failure tiers never score — single default
  difficulty). Pure / headless-testable; the resolver **reports**, the orchestrator **applies** the
  rewards (authority rule §2): crit line → bonus damage `ceil(weapon_base × L/3 × type_chart)` +
  **Inspirational** party buff (L≥3); success line → +1 meter (`BonusMeter.add_flat`); neutral line →
  refund 1 Stamina. Rewards `[ASSUMPTION]`.

---

## 5. View + orchestrator (implemented)

Built procedurally in GDScript (no hand-authored `.tscn` for the components — `combat.tscn` is just
the root `Control` with `combat.gd`). View nodes bind to logic signals; they never own game state.

- **`ReelStrip`** (`ui/reel_strip.gd`, Control) — scrolls a column of tier-colored cells and snaps to
  a target index. `configure(reel)`, `play_to(target_index, delay)`, signal `strip_settled`.
  Tunables: `SPIN_DURATION` (1.15s), `REPEATS`, `VISIBLE_CELLS`.
- **`CombatantPanel`** (`ui/combatant_panel.gd`, Panel) — name + HP bar + Bonus Meter + Stamina + the
  effective-stat readout (`MGT FIN VIG FOC GRT LCK`) + the status line (active effects, polarity-
  colored: buff green / debuff orange; STUNNED shown as an orange debuff); `bind(combatant)`.
- **`TurnOrderBar`** (`ui/turn_order_bar.gd`, Panel) — `set_order(order)`, `set_current(combatant)`.
- **`Combat`** (`combat.gd`, Control) — builds the 1v1 scenario + UI, wires every signal, owns the
  **SPIN** (= commit Main 1 + spin, or roll the stun gate when STUNNED) / **END TURN** buttons and the
  Splice / Fire-Ultimate **toggles** (which drive the `MainPhasePlan` preview), the scrollable combat
  log, runs the loop in §2, applies payline hits, shows the centered victory/defeat card + restart.
  Builds Martin with the Padded Jerkin (Might/Finesse/Luck) and a 15-cap meter; the rat with no gear.
  Tunables: `STRIP_STAGGER` (0.25s), `ENEMY_THINK_DELAY` (0.6s), `STUN_THRESHOLD` (−20). Window
  1280×800. UI is repositioned adaptively below the panel height so rows can't overlap the header.

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

**20 suites**, all green: `test_bonus_meter`, `test_combatant`, `test_turn_manager`,
`test_phase_manager`, `test_action_reel`, `test_effect`, `test_resource_pool`, `test_crushing_slow`,
`test_reel_splice`, `test_main_phase_plan`, `test_ultimate_sticky_wild`, `test_payline_library`,
`test_payline_resolver`, `test_payline_grid`, `test_payline_rewards`, `test_stats`,
`test_initiative_tiebreak`, `test_might_damage`, `test_stun`, and `test_combat_loop` (full
integration through the real managers/resolver). Each prints `… TEST PASSED/FAILED` and exits
non-zero on failure. New combat logic is written **test-first** (red → green). `gen_damage_types.gd`
regenerates the 6 type `.tres` (not a suite).

---

## 7. Combat systems — implemented (this branch)

All ten threads are **built and test-green**; their contracts live with their owners in §3–§5. Each
has a design spec in `docs/superpowers/specs/`; the autonomous balance/`[ASSUMPTION]` calls are in
`docs/superpowers/DECISIONS-LOG.md`.

- **`Effect` + Crushing→Slow** — the resolver **reports** `rider_effect_id` on a crit-success of a
  riding type; the orchestrator attaches `&"slow"` (`INITIATIVE_MOD` −20 / 2 turns) to the defender,
  whose `current_initiative` is re-derived via `recompute_initiative()`.
- **Stacking control debuffs (merge-by-id)** — `Combatant.attach_effect` merges any re-applied effect
  by `id` (never a second instance). SLOW stacks with diminishing returns (`stack_magnitudes
  [-20, -10, -5]`, cap −35) and refreshes duration; non-stacking effects only refresh. Kills the old
  unbounded-additive bug for every effect.
- **`ResourcePool` (Stamina only)** — regen in `on_upkeep`, spent in Main 1, shown on the panel.
- **Staged Main Phase 1 (`MainPhasePlan`)** — Splice / Fire-Ultimate are toggles that only PREVIEW;
  SPIN commits atomically. `PhaseManager` pauses at Main 1 (`proceed_to_combat()` enters Combat).
- **Main-Phase reel splice** — `Combatant.try_splice_reel(...)`: additive +1 Storm reel, 2 STA, this
  turn only, 5-reel cap; excluded from the payline grid.
- **Sticky-Wild Ultimate (crit-bias redesign)** — `Combatant.fire_sticky_wild(weapon_reel_count,
  spins)` costs ONLY the meter (PC cap **15**); makes **ALL weapon reels** crit-**biased**
  (`WILD_CRIT_CHANCE 0.65`, not forced) for 2 spins → varied crit grids. The other five archetypes
  (`EXTRA_SPINS`, `CASCADE`, `MULTIPLIER_CASCADE`, `HOLD_RESPIN`, `PICKEM`) are **deferred**.
- **Paylines** — `PaylineLibrary` (line geometry) + `PaylineResolver` (scoring); the resolver owns
  the 3×W weapon grid and emits `paylines_resolved`. Orchestrator applies: crit line → bonus damage
  (length-scaled, `ceil`) + Inspirational party buff (L≥3); success → +1 meter; neutral → refund
  1 STA. `extra_lines` hook reserved for Luck.
- **5+1 stat system + Gear** — `Stats` (Might/Finesse/Vigor/Focus/Grit/Luck) + `Gear`; `Combatant`
  derives HP / pool / meter-floor in `apply_stats()`; Might → flat per-hit damage via the resolver's
  `flat_damage_bonus`; Finesse → initiative + the `TurnManager` tie-break (Finesse, then a stored d10
  roll); Luck → `apply_luck()` adds crit faces to weapon reels.
- **STUNNED** — `Combatant.evaluate_stun` flags STUNNED at turn start (init < −20, anti-lock = can't
  be stunned two turns running); the orchestrator runs a Main-1 d100 gate (`stun_check_passed`: 51+
  recovers to a full turn, 01–50 loses the turn; PC presses SPIN, NPC auto-rolls).
- **Reel-face shuffle + round-up** — `ActionReel.make_default` shuffles faces (balance-neutral); all
  damage/heal math is `ceil` (project convention).

---

## 8. Deferred to DESIGN §8 (no code design yet)

`Class` (HP seed, reel/talent identity, `meter_floor`, `ultimate_archetype`), `EncounterTable`,
`RewardTable`, the talent system, and the world/hub structure. Post-prototype — see `DESIGN.md §8`,
§11, §12. Do not build speculatively (CLAUDE.md §7 YAGNI).

> **These are exactly what the upcoming content-design pause addresses** (races / classes / abilities
> / buffs-debuffs — see `HANDOFF.md §6`). When that design firms up, this is where the new code lands
> (new `Effect`s, Main-1 actions, Ultimate archetypes — riding the existing hooks, not new
> architecture), alongside full N-vs-M party combat (the systems are already party-ready; only the
> prototype *scenario* is 1v1).

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
