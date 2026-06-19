# ARCHITECTURE.md — Bunnies combat architecture

> **Status:** Living reference for the **as-built** combat system (vertical-slice prototype) plus
> concrete stub contracts for the next combat classes. **`DESIGN.md` is the source of truth for
> the design; this doc describes the code.** If they disagree, `DESIGN.md` wins — flag it.
> Naming convention is LOCKED in `CLAUDE.md §2` (classes PascalCase, files snake_case, signals
> snake_case **past-tense** like `spin_resolved`; handlers `_on_<emitter>_<signal>`).
>
> **Scope of this doc:** the combat system as it exists today + near-term combat stubs
> (`Effect`, `Ultimate`, `ResourcePool`). World/meta classes (`Class`, `EncounterTable`,
> `RewardTable`, talents) remain a `DESIGN.md §8` sketch — not yet designed in code.

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
      types/              slashing.tres · piercing.tres · crushing.tres ·
                          storm.tres · mystic.tres · earth.tres   (the 6-type chart, [ASSUMPTION] values)
    combat_resolver.gd    CombatResolver  (pure calculator)
    combatant.gd          Combatant
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

---

## 4. Combat logic (implemented)

### `CombatResolver` — `combat/combat_resolver.gd` (extends Node) — pure calculator
- nested `class AttackResult { face, damage_type, base_damage, final_damage:int, meter_gain:int }`
- `@export meter_charge_weights: Array[int] = [0,0,1,2,3]` (`[ASSUMPTION]`)
- `resolve_combat_phase(reels: Array[ActionReel], base_damage: float, target_type: DamageType = null) -> Array[AttackResult]`
  — each reel resolves **independently**; damage = `base × face.multiplier × type_chart`, rounded;
  non-damaging tiers deal 0. Emits `spin_started`, `damage_applied(attack)` per reel,
  `meter_charged(total)`, `spin_resolved(attacks)`. (The orchestrator may use the return value
  and apply effects itself — see §2.)

### `Combatant` — `combat/combatant.gd` (extends RefCounted)
- config: `display_name`, `is_player`, `max_hp`, `weapon`, `defense_type: DamageType`, `bonus_meter`
- live: `hp`, `current_initiative` (the turn-order sort key)
- **signals:** `hp_changed(hp, max_hp)`, `defeated`
- `start_combat()` (seed hp), `take_damage(amount)` (clamps at 0, fires `defeated` once), `is_alive()`

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
- `start_turn()` (runs Upkeep→Main 1→Combat, then **pauses** for the spin),
  `resume_after_combat()` (Main 2→End→`turn_finished`)

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
`test_action_reel`, and `test_combat_loop` (full integration through the real managers/resolver).
Each prints `… TEST PASSED/FAILED` and exits non-zero on failure. New combat logic is written
**test-first** (red → green). `gen_damage_types.gd` regenerates the 6 type `.tres`.

---

## 7. Near-term designed stubs (NOT yet built)

Concrete contracts for the next combat classes (DESIGN §8, §4.9, §10 Dec 6, §11 A4). Build
test-first when picked up. Signatures follow the locked convention.

```gdscript
# combat/resources/effect.gd — buffs/debuffs/riders applied BY reel faces (DESIGN §11 A4, §4.1).
# Reel faces APPLY effects; they don't contain them. Crushing→Slow is the first target rider.
class_name Effect
extends Resource
enum Kind { INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT, REEL_FACE_EDIT }
@export var id: StringName = &""
@export var kind: Kind = Kind.INITIATIVE_MOD
@export var magnitude: float = 0.0
@export var duration: int = 1            # turns/rounds remaining; ticks down in Upkeep/End
# func apply(target: Combatant) -> void        # on attach
# func tick(target: Combatant) -> void         # each Upkeep/End; decrement duration
# func is_expired() -> bool
```

```gdscript
# combat/resource_pool.gd — Stamina/Focus/Mana, spent in Main 1 (DESIGN §10 Dec 6).
# FULLY INDEPENDENT of BonusMeter. Gates abilities and additive reel-count modifiers.
class_name ResourcePool
extends RefCounted
var stamina: int = 0 ;  var max_stamina: int = 0
var focus: int = 0   ;  var max_focus: int = 0
var mana: int = 0    ;  var max_mana: int = 0
# signal pool_changed(kind, value, max)
# func can_afford(cost: Dictionary) -> bool
# func spend(cost: Dictionary) -> bool
# func regen() -> void                          # Upkeep
```

```gdscript
# combat/ultimate.gd — the armed ability fired by a full BonusMeter (DESIGN §4.9).
# Cost is the meter ONLY (never the ResourcePool). One archetype per class = identity.
class_name Ultimate
extends RefCounted
enum Archetype { STICKY_WILD, EXTRA_SPINS, CASCADE, MULTIPLIER_CASCADE, HOLD_RESPIN, PICKEM }
var archetype: Archetype = Archetype.EXTRA_SPINS
# func can_fire(meter: BonusMeter) -> bool       # meter.is_armed()
# func fire(ctx) -> void                          # apply effect, then meter.consume()
```

**Wiring when built:** `PhaseManager` Main 1 spends `ResourcePool` to add/subtract reels (additive to
the weapon band) and to arm abilities that attach `Effect`s; `TurnManager` ticks `Effect` durations in
Upkeep/End and re-sorts when `current_initiative` changes; firing an `Ultimate` is a player action in
Main 1/2 once `BonusMeter.is_armed()`.

---

## 8. Deferred to DESIGN §8 (no code design yet)

`Class` (HP seed, reel/talent identity, `meter_floor`, `ultimate_archetype`), `EncounterTable`,
`RewardTable`, the talent system, and the world/hub structure. Post-prototype — see `DESIGN.md §8`,
§11, §12. Do not build speculatively (CLAUDE.md §7 YAGNI).
