# Ability/Talent Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compress each class's ability ladder from L5/L7/L9 to L2/L3/L4, add a bespoke always-on
passive per class at L5, and add a 6-point talent-perk economy across L5-10, per the locked spec
`docs/superpowers/specs/2026-07-23-ability-talent-redesign-design.md`.

**Architecture:** Mechanical changes (level-gate numbers, a real level cap, the ENDGAME toggle)
land first and are independently verifiable via the existing test suite. Passive/perk CONTENT
(the actual 7 passive designs and the 17-perk list) is proposed in this plan — concretely, not as
placeholders — but two tasks are explicit **STOP-AND-CONFIRM content checkpoints**: do not execute
any task past a checkpoint until the player has approved it. Implementation tasks follow the
same bespoke-GDScript-method pattern this codebase already uses for every ability (no new rules
framework).

**Tech Stack:** GDScript (Godot 4.6), headless test suite (`Godot_v4.6.3-stable_win64_console.exe
--headless --path <repo> --script res://tests/test_<name>.gd`). The Godot executable lives ONE
DIRECTORY ABOVE this repo, at `C:\bunnies\bunnies-main\`, not inside
`C:\bunnies\bunnies-main\bunnies\`.

## Global Constraints

- Level cap: hard-enforced 10 (`combat/combatant.gd`'s `level` field).
- Ability unlock levels: 2/3/4 (was 5/7/9), same per-class relative order — no reordering.
- Passives unlock at L5, always-on, no staging/cost/cooldown.
- Talent points: 6 total, one per level 5→10, one-time-pick (no stacking), derived not stored.
- Ultimate gating and the gear-rarity ladder (1/3/5/7/9) are explicitly UNCHANGED — do not touch
  `RarityVisuals.min_level_for()` or any Ultimate-staging code in this plan.
- Respec (swap an already-picked perk) is town-only; view-only elsewhere — mirrors
  `InventoryMenuPanel`'s existing `vault_available` pattern exactly.
- New input action `toggle_talents` bound to `N` (physical keycode 78, confirmed free).
- Every task that touches game logic ends with a real headless test run, not just "should compile."
- **Tasks 4 and 12 are content-approval checkpoints, not code tasks.** Whoever executes this plan
  (human or subagent-driven-development) MUST stop and get explicit player sign-off on the content
  presented there before starting the tasks that depend on it (5-11 depend on Task 4; 13-14 depend
  on Task 12).

---

## Task 1: Level cap + ENDGAME toggle

**Files:**
- Modify: `combat/combatant.gd` (the `level` field, ~line 128-131)
- Modify: `combat/combat.gd:216` (`pc.level = 9` in the ENDGAME toggle branch)
- Test: `tests/test_character_level.gd` (extend), `tests/test_endgame_level.gd` (update)

**Interfaces:**
- Produces: `Combatant.MAX_LEVEL: int = 10` (const), `Combatant.level` now clamps to `[1, MAX_LEVEL]`
  on assignment via an inline setter.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_character_level.gd` (append before `quit()`):

```gdscript
	var cap_c: Combatant = Combatant.new()
	cap_c.level = 999
	_check(cap_c.level == Combatant.MAX_LEVEL, "level assignment clamps to MAX_LEVEL (10)")
	cap_c.level = -5
	_check(cap_c.level == 1, "level assignment clamps to a minimum of 1")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_level.gd`
Expected: `FAIL level assignment clamps to MAX_LEVEL (10)` (property `MAX_LEVEL` doesn't exist yet —
this is a parse/runtime error until Step 3 lands, which is fine, that's the point of this step).

- [ ] **Step 3: Add the clamp**

In `combat/combatant.gd`, replace the existing:

```gdscript
## Character level — gates extra_abilities (spec 2026-07-01). Default 1 = only the L1 base ability
## + nothing extra. Still a test/tester knob, not driven by [member xp] yet — the full leveling
## curve/level-up effects are deferred (docs/design-bible/22-leveling-and-progression.md).
var level: int = 1
```

with:

```gdscript
## Hard level cap (spec 2026-07-23 §2) — talent points stop generating here, and no code path
## currently has any reason to exceed it.
const MAX_LEVEL: int = 10

## Character level — gates extra_abilities (L2/L3/L4, spec 2026-07-23) and unlocks the L5 passive
## + L5-10 talent points (talent_points_earned()). Clamped to [1, MAX_LEVEL] on assignment — a real,
## enforced cap (spec 2026-07-23 §2), unlike the pre-2026-07-23 unbounded field. Still a test/tester
## knob, not driven by [member xp] yet — the full leveling curve/level-up moment is deferred
## (docs/design-bible/22-leveling-and-progression.md; spec 2026-07-23 §8).
var level: int = 1:
	set(value):
		level = clampi(value, 1, MAX_LEVEL)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_level.gd`
Expected: all lines print `ok `, no `FAIL`.

- [ ] **Step 5: Update the ENDGAME toggle**

In `combat/combat.gd`, change line 216 from `pc.level = 9` to `pc.level = 10`. Update
`tests/test_endgame_level.gd` line 14 from `c.level = 9` to `c.level = 10` (same intent: "high
enough to unlock everything," now aligned with the real cap).

- [ ] **Step 6: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_endgame_level.gd`
Expected: all lines print `ok `.

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/combat.gd tests/test_character_level.gd tests/test_endgame_level.gd
git commit -m "feat(leveling): enforce a real level cap of 10, bump ENDGAME toggle to match"
```

---

## Task 2: Ability unlock-level compression (L5/L7/L9 → L2/L3/L4)

**Files:**
- Modify: `combat/class_library.gd` (all 7 `_ability(...)` triples)
- Modify: `combat/ui/ability_menu_panel.gd` (base-ability row label)
- Modify: any test asserting a specific class's extra-ability unlock level (discovered via grep,
  see Step 4)
- Test: `tests/test_ability_menu_panel.gd` (base-ability label), plus every test touched by Step 4

**Interfaces:**
- Consumes: `AbilityDef.unlock_level` (existing field, `combat/resources/ability_def.gd`),
  `Combatant.unlocked_extra_abilities()` (existing, `combat/combatant.gd:643`) — neither changes
  shape, only the authored numbers passed into `_ability()` change.

- [ ] **Step 1: Change the authored unlock levels**

In `combat/class_library.gd`, for **every one of the 7 `_ability(...)` triples**, change the
second argument (`unlock_level`) from `5, 7, 9` to `2, 3, 4` — keep each class's own relative
order exactly as-is (first extra→2, second→3, third→4). The 7 triples and their exact current
lines:

```gdscript
# Warrior (lines 45-47)
_ability(&"sundering_strike", 2, 3, &"stamina", 0),
_ability(&"heroic_guard", 3, 3, &"stamina", 0),
_ability(&"second_wind", 4, 5, &"stamina", 4),
# Vanguard (lines 66-68)
_ability(&"bloodwrath", 2, 3, &"stamina", 0),
_ability(&"quake_slam", 3, 4, &"stamina", 0),
_ability(&"mountain_stance", 4, 5, &"stamina", 4),
# Skirmisher (lines 88-90)
_ability(&"feint_riposte", 2, 3, &"stamina", 0),
_ability(&"quickstep", 3, 3, &"stamina", 0),
_ability(&"riposte_storm", 4, 4, &"stamina", 3),
# Chancer (lines 111-113)
_ability(&"loaded_dice", 2, 3, &"mana", 0),
_ability(&"jinx_the_odds", 3, 3, &"mana", 0),
_ability(&"double_or_nothing", 4, 0, &"mana", 7),  # cost computed at cast time (Task 24)
# Ranger (lines 132-134)
_ability(&"aimed_shot", 2, 3, &"stamina", 0),
_ability(&"snare_trap", 3, 4, &"stamina", 0),
_ability(&"crippling_shot", 4, 5, &"stamina", 3),
# Seer (lines 155-157)
_ability(&"hex", 2, 4, &"mana", 0),
_ability(&"foresight", 3, 4, &"mana", 0),
_ability(&"mana_surge", 4, 6, &"mana", 4),
# Warden (lines 178-180)
_ability(&"entangle", 2, 4, &"mana", 0),
_ability(&"regrowth", 3, 4, &"mana", 0),
_ability(&"bastion", 4, 6, &"mana", 4),
```

Only the middle number changes on each line — `cost`/`resource`/`cooldown_turns` (the other 3
args) are untouched, per the spec's "level-gate change only, not a balance pass."

- [ ] **Step 2: Base-ability display label for consistency**

In `combat/ui/ability_menu_panel.gd`, the `_build_row()` function currently renders every row's
`status` text from `cooldown_text()`, which returns `"Ready"` for the base ability unconditionally
(line 50-51: `if c == null or id == c.ability_id: return "Ready"`). Add an explicit "Unlocked at
L1" tag so the base ability reads consistently with the other 3 rows once those show unlock
levels (this step doesn't add unlock-level text to the OTHER 3 rows — they don't show one today
either, and adding that is out of scope; this step only stops the base ability from looking
un-leveled by comparison in the row's title). Change line 124 from:

```gdscript
	btn.text = "%s  (%s)" % [AbilityCatalog.display_name(id), cost_text(plan, c, id)]
```

to:

```gdscript
	var level_tag: String = "  [L1]" if (c != null and id == c.ability_id) else ""
	btn.text = "%s%s  (%s)" % [AbilityCatalog.display_name(id), level_tag, cost_text(plan, c, id)]
```

- [ ] **Step 3: Write the label test**

Add to `tests/test_ability_menu_panel.gd` (find the existing test that builds a panel + combatant
and asserts on `row_ids()`/button text; append a new check):

```gdscript
	var base_btn: Button = panel._row_buttons[c.ability_id]
	_check("[L1]" in base_btn.text, "base ability row shows the [L1] tag")
```

(Match the existing file's variable names for `panel`/`c` — read the file first, it already
builds both before this point.)

- [ ] **Step 4: Discover and fix every test that relies on the old 5/7/9 levels**

Run:
```bash
grep -rn "\.level = [579]\b" tests/
```

For **each match**, read ~10 lines of surrounding context. Apply this rule:

- If the test constructs a **real class's** `Combatant` (via `ClassLibrary.make(id)` or
  `CharacterClass.build_combatant()`) and sets `.level` specifically to unlock/test ONE of these
  named abilities — `sundering_strike, heroic_guard, second_wind, bloodwrath, quake_slam,
  mountain_stance, feint_riposte, quickstep, riposte_storm, loaded_dice, jinx_the_odds,
  double_or_nothing, aimed_shot, snare_trap, crippling_shot, hex, foresight, mana_surge, entangle,
  regrowth, bastion` — remap the level using **5→2, 7→3, 9→4**.
- If the test is checking **gear rarity** (`can_equip`, `RarityVisuals`, Legendary/Epic/Rare gear,
  files like `test_gear_equip_validation.gd`, `test_gear_equip_unequip.gd`,
  `test_weapon_empowerment.gd`, `test_inventory_menu_panel_transfer.gd`) — **leave the level value
  unchanged**. The gear-rarity ladder (1/3/5/7/9) is explicitly not touched by this plan.
- If the test uses a **synthetic** `AbilityDef.new()` with a hand-set `unlock_level` (like
  `test_character_level.gd`'s `a5`/`a7`/`a9`) to test the generic filter mechanism, not a real
  class's authored ability — **leave it unchanged**; it's testing `unlocked_extra_abilities()`'s
  logic, which didn't change.
- If the test just wants "this combatant has every extra ability unlocked" with no specific level
  under test (e.g. UI-state tests like `test_ability_menu_state.gd`, `test_ability_cooldown.gd`) —
  change the value to **4** (the new "everything's unlocked" floor for abilities specifically).

- [ ] **Step 5: Run the full suite and fix stragglers**

Run every test file under `tests/` (this project's standing full-sweep convention — see
`CLAUDE.md` §8's "Verified-by-machine" pattern). Any remaining failure not covered by Step 4's
rule is a real gap in that rule — read the failing test, decide which bucket it actually belongs
to, fix it, and re-run. Do not move on until the full sweep is clean (the handful of
known-intermittent teardown-only SIGSEGV flakes documented elsewhere in this project's history are
the only acceptable non-clean result — confirm any such failure is clean on an individual retry
before treating it as a flake, not a real regression).

- [ ] **Step 6: Commit**

```bash
git add combat/class_library.gd combat/ui/ability_menu_panel.gd tests/
git commit -m "feat(abilities): compress the extra-ability unlock ladder from L5/L7/L9 to L2/L3/L4"
```

---

## Task 3: Passive scaffolding (data model + hook signatures)

**Files:**
- Modify: `combat/resources/character_class.gd` (new `passive_ability_id` field)
- Modify: `combat/class_library.gd` (`build_combatant()` copies it — see Step 2)
- Modify: `combat/combatant.gd` (new `passive_ability_id` field, 4 new dispatch stub methods, hook
  the 3 existing multiplier/resist functions + `_on_paylines_resolved`'s future call site)
- Modify: `combat/combat.gd:1732` (pass `_defender` into `outgoing_damage_multiplier()`)
- Test: `tests/test_passive_scaffold.gd` (new)

**Interfaces:**
- Produces: `Combatant.passive_ability_id: StringName`, `Combatant.passive_outgoing_multiplier
  (defender: Combatant = null) -> float`, `Combatant.passive_incoming_multiplier() -> float`,
  `Combatant.passive_dot_damage_multiplier() -> float`, `Combatant.passive_max_mana_multiplier()
  -> float`, `Combatant.passive_on_payline_scored(tier: ReelFace.ResultTier) -> void` — all default
  to a neutral no-op (1.0 multiplier / do-nothing) since no class dispatches into them yet (that's
  Tasks 5-11).

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_scaffold.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.level = 10
	c.passive_ability_id = &"does_not_exist_yet"
	_check(c.passive_outgoing_multiplier() == 1.0, "unknown passive id is a neutral outgoing multiplier")
	_check(c.passive_incoming_multiplier() == 1.0, "unknown passive id is a neutral incoming multiplier")
	_check(c.passive_dot_damage_multiplier() == 1.0, "unknown passive id is a neutral DoT multiplier")
	_check(c.passive_max_mana_multiplier() == 1.0, "unknown passive id is a neutral max-mana multiplier")
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)  # must not crash with no bonus_meter

	var below5: Combatant = Combatant.new()
	below5.level = 4
	below5.passive_ability_id = &"anything"
	_check(below5.passive_outgoing_multiplier() == 1.0, "below L5, passive dispatch is skipped entirely")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_scaffold.gd`
Expected: FAIL / parse error — none of these members exist yet.

- [ ] **Step 3: Add `passive_ability_id` to `CharacterClass` and `Combatant`**

In `combat/resources/character_class.gd`, add alongside the existing `ability_id` (after line 58's
`ultimate_id`):

```gdscript
## This class's L5 always-on passive (spec 2026-07-23 §4). Empty until Task 4's content checkpoint
## is approved and Tasks 5-11 assign real ids. Copied onto Combatant.passive_ability_id by
## build_combatant() the same way ability_id already is.
@export var passive_ability_id: StringName = &""
```

In `combat/class_library.gd`'s `build_combatant()` — wait, `build_combatant()` lives on
`CharacterClass`, not `ClassLibrary`. In `combat/resources/character_class.gd`'s
`build_combatant()`, add right after the existing `c.ultimate_id = ultimate_id` line:

```gdscript
	c.passive_ability_id = passive_ability_id
```

In `combat/combatant.gd`, add alongside the existing `ultimate_id` field (near line 126):

```gdscript
## This class's L5 always-on passive id (spec 2026-07-23 §4) — dispatches through
## passive_outgoing_multiplier()/passive_incoming_multiplier()/passive_dot_damage_multiplier()/
## passive_max_mana_multiplier()/passive_on_payline_scored(), each gated on level >= 5 internally.
## Empty = no passive (enemies, or a class not yet wired).
var passive_ability_id: StringName = &""
```

- [ ] **Step 4: Add the 4 multiplier/resist dispatch stubs + the event-hook stub**

In `combat/combatant.gd`, add these 5 new methods directly below `incoming_damage_multiplier()`
(after line 551):

```gdscript
## Multiplier contribution from this combatant's L5 passive (spec 2026-07-23 §4), applied to
## OUTGOING damage. 1.0 (neutral) below L5, with no passive, or for an id with no outgoing hook.
## [param defender] is the current target — some passives (e.g. a debuff-conditional bonus) need
## to read the DEFENDER's state, not just the attacker's own.
func passive_outgoing_multiplier(defender: Combatant = null) -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		_:
			return 1.0

## Multiplier contribution from this combatant's L5 passive, applied to INCOMING damage. 1.0
## (neutral) below L5, with no passive, or for an id with no incoming hook.
func passive_incoming_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		_:
			return 1.0

## Multiplier contribution from this combatant's L5 passive, applied to incoming
## DAMAGE_OVER_TIME tick damage (stacks multiplicatively with Vigor's existing dot_damage_
## multiplier() floor). 1.0 (neutral) below L5, with no passive, or for an id with no DoT hook.
func passive_dot_damage_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		_:
			return 1.0

## Multiplier contribution from this combatant's L5 passive, applied to max Mana in apply_stats().
## 1.0 (neutral) below L5, with no passive, or for an id with no Mana hook.
func passive_max_mana_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		_:
			return 1.0

## Event hook: called once per scored payline hit (combat.gd's _on_paylines_resolved), for a
## passive that reacts to paylines scoring rather than contributing a multiplier. No-op below L5,
## with no passive, or for an id with no payline hook.
func passive_on_payline_scored(_tier: ReelFace.ResultTier) -> void:
	if level < 5 or passive_ability_id == &"":
		return
	match passive_ability_id:
		_:
			pass
```

Now wire the 3 multiplier functions to multiply in their passive term. Change
`outgoing_damage_multiplier()` (line 537-542) from:

```gdscript
func outgoing_damage_multiplier() -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and not e.affects_incoming:
			total *= e.effective_magnitude()
	return total
```

to:

```gdscript
func outgoing_damage_multiplier(defender: Combatant = null) -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and not e.affects_incoming:
			total *= e.effective_magnitude()
	total *= passive_outgoing_multiplier(defender)
	return total
```

Change `incoming_damage_multiplier()` (line 546-551) similarly, adding `total *=
passive_incoming_multiplier()` before its `return total`.

Change `dot_damage_multiplier()` (line 555-556) from:

```gdscript
func dot_damage_multiplier() -> float:
	return clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
```

to:

```gdscript
func dot_damage_multiplier() -> float:
	var base: float = clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
	return base * passive_dot_damage_multiplier()
```

- [ ] **Step 5: Wire the `outgoing_damage_multiplier()` call site**

In `combat/combat.gd:1732`, change:

```gdscript
	var dmg_mult: float = _attacker.outgoing_damage_multiplier() * _defender.incoming_damage_multiplier()
```

to:

```gdscript
	var dmg_mult: float = _attacker.outgoing_damage_multiplier(_defender) * _defender.incoming_damage_multiplier()
```

- [ ] **Step 6: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_scaffold.gd`
Expected: all lines print `ok `.

- [ ] **Step 7: Run the full suite (regression check on the signature change)**

Run every test file under `tests/` — `outgoing_damage_multiplier()`'s signature changed (new
optional param), so confirm nothing else called it positionally in a way that breaks. Expected:
clean, same as Task 2 Step 5.

- [ ] **Step 8: Commit**

```bash
git add combat/resources/character_class.gd combat/combatant.gd combat/combat.gd tests/test_passive_scaffold.gd
git commit -m "feat(passives): add passive_ability_id + neutral dispatch scaffolding for L5 class passives"
```

---

## Task 4: 🛑 CONTENT CHECKPOINT — 7 per-class passive designs

**This is not a code task.** Present the following proposed passive designs to the player and get
explicit approval before starting Tasks 5-11. Each is chosen to hook into Task 3's existing
scaffolding with no new hook shapes, and each is thematically tied to that class's existing kit
identity (per the spec §4 and the player's own example).

| Class | Passive name | Effect | Hook |
|---|---|---|---|
| Warrior | **Last Stand** | +20% outgoing damage while at or below 30% HP | `passive_outgoing_multiplier` (self, HP-conditional) |
| Vanguard | **Bulwark** | −15% incoming damage while above 50% HP | `passive_incoming_multiplier` (self, HP-conditional) |
| Skirmisher | **Opportunist** | +15% outgoing damage vs. a defender that is Slowed, Rooted, or Stunned-last-turn | `passive_outgoing_multiplier` (defender-conditional) |
| Chancer | **House Edge** | +1 flat Bonus Meter charge whenever any payline scores | `passive_on_payline_scored` (event hook) |
| Ranger | **Steady Aim** | +10% outgoing damage vs. a Hunter's-Marked defender | `passive_outgoing_multiplier` (defender-conditional) |
| Seer | **Arcane Reservoir** | +20% max Mana | `passive_max_mana_multiplier` (self, stat-recompute) |
| Warden | **Deep Roots** | −15% incoming DAMAGE_OVER_TIME tick damage (stacks with Vigor's existing resist) **+ passive HP regen: heal `ceil(max_hp / 16)` every Upkeep** | `passive_dot_damage_multiplier` (self) **+ new `passive_upkeep_heal_amount` hook (self)** |

All magnitudes are `[ASSUMPTION]` per this project's convention (CLAUDE.md §4) — tune by playtest,
do not treat these numbers as final. Warrior's design matches the player's own example from the
brainstorm exactly. Skirmisher's debuff-check condition reuses the exact expression Crippling Shot
already uses (`combat/combat.gd:1875`) for consistency.

**PLAYER-APPROVED 2026-07-23**, with one change to Warden's Deep Roots: added a passive HP regen
component (`ceil(max_hp / 16)` healed every Upkeep, rounded up) alongside the existing −15% DoT
resist. This needs a new hook not in Task 3's original scaffolding
(`passive_upkeep_heal_amount()`, added directly in Task 11 rather than reopening the already-
reviewed Task 3 — the same "extend combatant.gd with what the task needs" pattern every other
passive task already follows for its own hook). Task 11 below reflects the updated design. All
other 6 passives approved exactly as proposed — proceeding to Task 5.

---

## Task 5: Warrior passive — Last Stand

**Files:**
- Modify: `combat/class_library.gd` (Warrior's `c.passive_ability_id = &"last_stand"`)
- Modify: `combat/combatant.gd` (`passive_outgoing_multiplier()`'s match arm)
- Modify: `combat/ui/ability_catalog.gd` (or wherever `AbilityCatalog` lives — confirm path first;
  add a `&"last_stand"` description entry)
- Test: `tests/test_passive_last_stand.gd` (new)

**Interfaces:**
- Consumes: `Combatant.passive_outgoing_multiplier(defender)` scaffold from Task 3.

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_last_stand.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"last_stand"
	c.level = 5
	c.max_hp = 100
	c.hp = 30  # exactly 30% — the threshold is inclusive
	_check(c.passive_outgoing_multiplier() == 1.2, "Last Stand: +20% at exactly 30% HP")
	c.hp = 31
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: neutral just above 30% HP")
	c.level = 4
	c.hp = 10
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: inactive below L5 even at low HP")

	var wc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(wc.passive_ability_id == &"last_stand", "Warrior's CharacterClass carries the passive id")
	var pc: Combatant = wc.build_combatant(true)
	_check(pc.passive_ability_id == &"last_stand", "build_combatant() copies passive_ability_id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_last_stand.gd`
Expected: FAIL (no match arm yet, `ClassLibrary.make(&"warrior").passive_ability_id` is still `&""`).

- [ ] **Step 3: Implement**

In `combat/combatant.gd`'s `passive_outgoing_multiplier()`, change the `match` body from:

```gdscript
	match passive_ability_id:
		_:
			return 1.0
```

to:

```gdscript
	match passive_ability_id:
		&"last_stand":
			return 1.2 if (float(hp) / float(maxi(max_hp, 1))) <= 0.30 else 1.0
		_:
			return 1.0
```

In `combat/class_library.gd`, inside the `&"warrior":` branch, add (near the existing
`c.ultimate_id = &"wild"` line):

```gdscript
			c.passive_ability_id = &"last_stand"
```

Find `AbilityCatalog`'s file (it's referenced from `combat/ui/ability_menu_panel.gd` — confirm the
exact path via `grep -rn "class_name AbilityCatalog"`) and add an entry following its existing
per-id `display_name`/`description` convention:

```gdscript
&"last_stand": return "Last Stand"      # in display_name()'s match
&"last_stand": return "Passive: deals +20% damage while at or below 30% HP."  # in description()'s match
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_last_stand.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd combat/class_library.gd combat/ui/ability_catalog.gd tests/test_passive_last_stand.gd
git commit -m "feat(passives): Warrior Last Stand — +20% damage at/below 30% HP"
```

---

## Task 6: Vanguard passive — Bulwark

**Files:**
- Modify: `combat/class_library.gd` (Vanguard's `c.passive_ability_id = &"bulwark"`)
- Modify: `combat/combatant.gd` (`passive_incoming_multiplier()`'s match arm)
- Modify: `combat/ui/ability_catalog.gd` (description entry)
- Test: `tests/test_passive_bulwark.gd` (new)

**Interfaces:**
- Consumes: `Combatant.passive_incoming_multiplier()` scaffold from Task 3.

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_bulwark.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"bulwark"
	c.level = 5
	c.max_hp = 100
	c.hp = 51
	_check(c.passive_incoming_multiplier() == 0.85, "Bulwark: -15% just above 50% HP")
	c.hp = 50
	_check(c.passive_incoming_multiplier() == 1.0, "Bulwark: neutral at exactly 50% HP (threshold is exclusive)")
	c.level = 4
	c.hp = 100
	_check(c.passive_incoming_multiplier() == 1.0, "Bulwark: inactive below L5 even at full HP")

	var vc: CharacterClass = ClassLibrary.make(&"vanguard")
	_check(vc.passive_ability_id == &"bulwark", "Vanguard's CharacterClass carries the passive id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_bulwark.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `combat/combatant.gd`'s `passive_incoming_multiplier()`, add the match arm:

```gdscript
		&"bulwark":
			return 0.85 if (float(hp) / float(maxi(max_hp, 1))) > 0.50 else 1.0
```

In `combat/class_library.gd`'s `&"vanguard":` branch, add:

```gdscript
			c.passive_ability_id = &"bulwark"
```

In `AbilityCatalog`, add:

```gdscript
&"bulwark": return "Bulwark"
&"bulwark": return "Passive: takes 15% less damage while above 50% HP."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_bulwark.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd combat/class_library.gd combat/ui/ability_catalog.gd tests/test_passive_bulwark.gd
git commit -m "feat(passives): Vanguard Bulwark — -15% incoming damage above 50% HP"
```

---

## Task 7: Skirmisher passive — Opportunist

**Files:**
- Modify: `combat/class_library.gd` (Skirmisher's `c.passive_ability_id = &"opportunist"`)
- Modify: `combat/combatant.gd` (`passive_outgoing_multiplier()`'s match arm)
- Modify: `combat/ui/ability_catalog.gd` (description entry)
- Test: `tests/test_passive_opportunist.gd` (new)

**Interfaces:**
- Consumes: `Combatant.passive_outgoing_multiplier(defender)` scaffold from Task 3;
  `Combatant.has_effect(id)` (existing, `combat/combatant.gd:613`); `Combatant.stunned_last_turn`
  (existing field, referenced by `combat/combat.gd:1875`'s identical debuff-check expression).

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_opportunist.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"opportunist"
	c.level = 5

	var defender: Combatant = Combatant.new()
	_check(c.passive_outgoing_multiplier(defender) == 1.0, "Opportunist: neutral vs an undebuffed defender")

	defender.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.passive_outgoing_multiplier(defender) == 1.15, "Opportunist: +15% vs a Slowed defender")

	var defender2: Combatant = Combatant.new()
	defender2.attach_effect(EffectLibrary.make(&"rooted"))
	_check(c.passive_outgoing_multiplier(defender2) == 1.15, "Opportunist: +15% vs a Rooted defender")

	var defender3: Combatant = Combatant.new()
	defender3.stunned_last_turn = true
	_check(c.passive_outgoing_multiplier(defender3) == 1.15, "Opportunist: +15% vs a defender stunned last turn")

	_check(c.passive_outgoing_multiplier(null) == 1.0, "Opportunist: neutral with no defender reference")

	var sc: CharacterClass = ClassLibrary.make(&"skirmisher")
	_check(sc.passive_ability_id == &"opportunist", "Skirmisher's CharacterClass carries the passive id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_opportunist.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `combat/combatant.gd`'s `passive_outgoing_multiplier()`, add the match arm (alongside
`&"last_stand"` from Task 5):

```gdscript
		&"opportunist":
			if defender == null:
				return 1.0
			return 1.15 if (defender.has_effect(&"slow") or defender.has_effect(&"rooted") or defender.stunned_last_turn) else 1.0
```

In `combat/class_library.gd`'s `&"skirmisher":` branch, add:

```gdscript
			c.passive_ability_id = &"opportunist"
```

In `AbilityCatalog`, add:

```gdscript
&"opportunist": return "Opportunist"
&"opportunist": return "Passive: deals +15% damage against a target that's Slowed, Rooted, or was Stunned last turn."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_opportunist.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd combat/class_library.gd combat/ui/ability_catalog.gd tests/test_passive_opportunist.gd
git commit -m "feat(passives): Skirmisher Opportunist — +15% damage vs a debuffed defender"
```

---

## Task 8: Chancer passive — House Edge

**Files:**
- Modify: `combat/class_library.gd` (Chancer's `c.passive_ability_id = &"house_edge"`)
- Modify: `combat/combatant.gd` (`passive_on_payline_scored()`'s match arm)
- Modify: `combat/combat.gd` (`_on_paylines_resolved()` calls the new hook)
- Modify: `combat/ui/ability_catalog.gd` (description entry)
- Test: `tests/test_passive_house_edge.gd` (new)

**Interfaces:**
- Consumes: `Combatant.passive_on_payline_scored(tier)` scaffold from Task 3;
  `BonusMeter.add_flat(amount)` (existing, `combat/bonus_meter.gd:64`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_house_edge.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"house_edge"
	c.level = 5
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 15
	var before: int = c.bonus_meter.value
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c.bonus_meter.value == before + 1, "House Edge: +1 flat meter charge on any scored payline")

	c.level = 4
	var before2: int = c.bonus_meter.value
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c.bonus_meter.value == before2, "House Edge: inactive below L5")

	var no_meter: Combatant = Combatant.new()
	no_meter.passive_ability_id = &"house_edge"
	no_meter.level = 5
	no_meter.passive_on_payline_scored(ReelFace.ResultTier.CRIT_SUCCESS)  # must not crash with null bonus_meter

	var cc: CharacterClass = ClassLibrary.make(&"chancer")
	_check(cc.passive_ability_id == &"house_edge", "Chancer's CharacterClass carries the passive id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_house_edge.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `combat/combatant.gd`'s `passive_on_payline_scored()`, change the match body from:

```gdscript
	match passive_ability_id:
		_:
			pass
```

to:

```gdscript
	match passive_ability_id:
		&"house_edge":
			if bonus_meter != null:
				bonus_meter.add_flat(1)
		_:
			pass
```

In `combat/class_library.gd`'s `&"chancer":` branch, add:

```gdscript
			c.passive_ability_id = &"house_edge"
```

In `combat/combat.gd`'s `_on_paylines_resolved(hits: Array)` (line 2045), add the hook call as the
first line of the `for hit in hits:` loop body:

```gdscript
	for hit in hits:
		_attacker.passive_on_payline_scored(hit.tier)
		match hit.tier:
```

In `AbilityCatalog`, add:

```gdscript
&"house_edge": return "House Edge"
&"house_edge": return "Passive: gains +1 extra Bonus Meter charge whenever any payline scores."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_house_edge.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Run the payline regression tests**

Run every existing test file whose name contains `payline` (e.g. `tests/test_paylines.gd` or
similarly named files — confirm exact names via `grep -rl "PaylineResolver\|paylines_resolved"
tests/`). Expected: unaffected — House Edge only ADDS a meter charge when `passive_ability_id ==
&"house_edge"`, which no pre-existing test's `Combatant` sets.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/class_library.gd combat/combat.gd combat/ui/ability_catalog.gd tests/test_passive_house_edge.gd
git commit -m "feat(passives): Chancer House Edge — +1 meter charge on any scored payline"
```

---

## Task 9: Ranger passive — Steady Aim

**Files:**
- Modify: `combat/class_library.gd` (Ranger's `c.passive_ability_id = &"steady_aim"`)
- Modify: `combat/combatant.gd` (`passive_outgoing_multiplier()`'s match arm)
- Modify: `combat/ui/ability_catalog.gd` (description entry)
- Test: `tests/test_passive_steady_aim.gd` (new)

**Interfaces:**
- Consumes: `Combatant.passive_outgoing_multiplier(defender)` scaffold from Task 3 (already
  extended with the `defender == null` guard by Task 7).

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_steady_aim.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"steady_aim"
	c.level = 5

	var defender: Combatant = Combatant.new()
	_check(c.passive_outgoing_multiplier(defender) == 1.0, "Steady Aim: neutral vs an unmarked defender")

	defender.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(c.passive_outgoing_multiplier(defender) == 1.10, "Steady Aim: +10% vs a Marked defender")

	var rc: CharacterClass = ClassLibrary.make(&"ranger")
	_check(rc.passive_ability_id == &"steady_aim", "Ranger's CharacterClass carries the passive id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_steady_aim.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `combat/combatant.gd`'s `passive_outgoing_multiplier()`, add the match arm:

```gdscript
		&"steady_aim":
			return 1.10 if (defender != null and defender.has_effect(&"hunters_mark")) else 1.0
```

In `combat/class_library.gd`'s `&"ranger":` branch, add:

```gdscript
			c.passive_ability_id = &"steady_aim"
```

In `AbilityCatalog`, add:

```gdscript
&"steady_aim": return "Steady Aim"
&"steady_aim": return "Passive: deals +10% damage against a target marked by Hunter's Mark."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_steady_aim.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd combat/class_library.gd combat/ui/ability_catalog.gd tests/test_passive_steady_aim.gd
git commit -m "feat(passives): Ranger Steady Aim — +10% damage vs a Hunter's-Marked defender"
```

---

## Task 10: Seer passive — Arcane Reservoir

**Files:**
- Modify: `combat/class_library.gd` (Seer's `c.passive_ability_id = &"arcane_reservoir"`)
- Modify: `combat/combatant.gd` (`passive_max_mana_multiplier()`'s match arm, and `apply_stats()`'s
  max-Mana line)
- Modify: `combat/ui/ability_catalog.gd` (description entry)
- Test: `tests/test_passive_arcane_reservoir.gd` (new)

**Interfaces:**
- Consumes: `Combatant.passive_max_mana_multiplier()` scaffold from Task 3;
  `Combatant.apply_stats()` (existing, `combat/combatant.gd:454`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_arcane_reservoir.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"arcane_reservoir"
	c.level = 5
	c.base_max_mana = 20
	c.resource_pool = ResourcePool.new()
	c.apply_stats()
	_check(c.resource_pool.max_mana == 24, "Arcane Reservoir: +20% max Mana (20 -> 24)")

	c.level = 4
	c.apply_stats()
	_check(c.resource_pool.max_mana == 20, "Arcane Reservoir: inactive below L5")

	var sc: CharacterClass = ClassLibrary.make(&"seer")
	_check(sc.passive_ability_id == &"arcane_reservoir", "Seer's CharacterClass carries the passive id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_arcane_reservoir.gd`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `combat/combatant.gd`'s `passive_max_mana_multiplier()`, add the match arm:

```gdscript
		&"arcane_reservoir":
			return 1.2
```

In `combat/combatant.gd`'s `apply_stats()`, change the existing line:

```gdscript
		resource_pool.max_mana = (base_max_mana + s.focus) if base_max_mana > 0 else 0
```

to:

```gdscript
		resource_pool.max_mana = ceili((base_max_mana + s.focus) * passive_max_mana_multiplier()) if base_max_mana > 0 else 0
```

In `combat/class_library.gd`'s `&"seer":` branch, add:

```gdscript
			c.passive_ability_id = &"arcane_reservoir"
```

In `AbilityCatalog`, add:

```gdscript
&"arcane_reservoir": return "Arcane Reservoir"
&"arcane_reservoir": return "Passive: max Mana is increased by 20%."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_arcane_reservoir.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Run the resource-pool regression tests**

Run every test file whose name contains `mana`, `resource_pool`, or `seer` (grep to confirm exact
names). Expected: unaffected — `passive_max_mana_multiplier()` returns `1.0` for every combatant
whose `passive_ability_id != &"arcane_reservoir"`, so `ceili(x * 1.0) == x` for every pre-existing
test.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/class_library.gd combat/ui/ability_catalog.gd tests/test_passive_arcane_reservoir.gd
git commit -m "feat(passives): Seer Arcane Reservoir — +20% max Mana"
```

---

## Task 11: Warden passive — Deep Roots (revised 2026-07-23: adds passive HP regen)

**Files:**
- Modify: `combat/class_library.gd` (Warden's `c.passive_ability_id = &"deep_roots"`)
- Modify: `combat/combatant.gd` (`passive_dot_damage_multiplier()`'s match arm; new
  `passive_upkeep_heal_amount()` dispatch method, same neutral-below-L5/no-passive-id shape as the
  other 4 dispatch stubs from Task 3)
- Modify: `combat/combat.gd` (`_on_phase_changed()`'s UPKEEP branch calls the new hook and logs the
  heal, mirroring `_apply_dot()`'s existing beneficial-tick log line)
- Modify: `combat/ui/ability_catalog.gd` (description entry — mention both effects)
- Test: `tests/test_passive_deep_roots.gd` (new)

**Interfaces:**
- Consumes: `Combatant.passive_dot_damage_multiplier()` scaffold from Task 3 (already wired into
  `dot_damage_multiplier()` by Task 3 Step 4).
- Produces: `Combatant.passive_upkeep_heal_amount() -> int` — a NEW dispatch method, not part of
  Task 3's original scaffolding (that checkpoint's 7 designs didn't need it yet). Follows the exact
  same shape as Task 3's other 4 stubs: `if level < 5 or passive_ability_id == &"": return 0`, then
  a `match passive_ability_id` with a `_:  return 0` default. Deep Roots' arm returns
  `ceili(float(max_hp) / 16.0)`. `combat.gd` calls it once per Upkeep and applies it via the
  combatant's existing `heal()` method — this is a flat passive tick, not an `Effect`/DoT-style
  attached buff, so it does NOT go through `EffectLibrary`/`active_effects`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_passive_deep_roots.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"deep_roots"
	c.level = 5
	var neutral: Combatant = Combatant.new()
	# Vigor's own resist is 0 for a Combatant with no base_stats set, so the multiplier here is
	# purely the passive's contribution.
	_check(is_equal_approx(c.dot_damage_multiplier(), 0.85), "Deep Roots: -15% incoming DoT damage")
	_check(is_equal_approx(neutral.dot_damage_multiplier(), 1.0), "no passive: unaffected DoT multiplier")

	c.level = 4
	_check(is_equal_approx(c.dot_damage_multiplier(), 1.0), "Deep Roots: inactive below L5")

	# Passive HP regen: ceil(max_hp / 16), only at L5+.
	var r: Combatant = Combatant.new()
	r.passive_ability_id = &"deep_roots"
	r.level = 5
	r.max_hp = 100
	_check(r.passive_upkeep_heal_amount() == 7, "Deep Roots: ceil(100/16) = 7 HP regen")
	r.max_hp = 96
	_check(r.passive_upkeep_heal_amount() == 6, "Deep Roots: exact division still rounds via ceili (96/16 = 6)")
	r.level = 4
	_check(r.passive_upkeep_heal_amount() == 0, "Deep Roots: no regen below L5")
	_check(neutral.passive_upkeep_heal_amount() == 0, "no passive: no regen")

	var wc: CharacterClass = ClassLibrary.make(&"warden")
	_check(wc.passive_ability_id == &"deep_roots", "Warden's CharacterClass carries the passive id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_deep_roots.gd`
Expected: FAIL / parse error (`passive_upkeep_heal_amount()` doesn't exist yet).

- [ ] **Step 3: Implement**

In `combat/combatant.gd`'s `passive_dot_damage_multiplier()`, add the match arm:

```gdscript
		&"deep_roots":
			return 0.85
```

Directly below `passive_dot_damage_multiplier()`, add the new dispatch stub (same shape as the
other 4 from Task 3):

```gdscript
## Flat HP healed at this combatant's own Upkeep from its L5 passive (spec 2026-07-23 §4, revised
## same day to add Warden's regen). 0 below L5, with no passive, or for an id with no Upkeep-heal
## hook. Applied directly via heal() in combat.gd's UPKEEP phase handling — NOT an attached Effect.
func passive_upkeep_heal_amount() -> int:
	if level < 5 or passive_ability_id == &"":
		return 0
	match passive_ability_id:
		&"deep_roots":
			return ceili(float(max_hp) / 16.0)
		_:
			return 0
```

In `combat/class_library.gd`'s `&"warden":` branch, add:

```gdscript
			c.passive_ability_id = &"deep_roots"
```

In `combat/combat.gd`'s `_on_phase_changed()`, in the `UPKEEP` branch, add the regen call right
after `_apply_dot(_attacker)` (so a passive heal never masks whether a DoT tick was lethal — same
ordering rationale already documented for `on_upkeep()` vs. `_apply_dot()` immediately above it):

```gdscript
		_apply_dot(_attacker)
		var passive_heal: int = _attacker.passive_upkeep_heal_amount()
		if passive_heal > 0 and _attacker.is_alive():
			_attacker.heal(passive_heal)
			_log("  %s regenerates %d HP from Deep Roots." % [_attacker.display_name, passive_heal])
```

In `AbilityCatalog`, add:

```gdscript
&"deep_roots": return "Deep Roots"
&"deep_roots": return "Passive: takes 15% less damage from damage-over-time effects, and regenerates 1/16 of max HP (rounded up) every turn."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_passive_deep_roots.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Run the full suite (checkpoint after all 7 passives)**

Run every test file under `tests/`. This is the first full-suite run since Task 4's checkpoint —
confirm all 7 passives coexist cleanly (each dispatches only on its own id, so no cross-class
interference is expected) and nothing from Tasks 1-2's ability-level migration regressed. Pay
particular attention to any existing Warden combat-log/Upkeep test that asserts an exact log-line
sequence or HP value at L5+ — the new regen tick is a behavior change for any such fixture, not just
an addition.

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd combat/combat.gd combat/class_library.gd combat/ui/ability_catalog.gd tests/test_passive_deep_roots.gd
git commit -m "feat(passives): Warden Deep Roots — -15% incoming DoT damage + passive HP regen"
```

---

## Task 12: 🛑 CONTENT CHECKPOINT — talent perk list (universal + class-flavored)

**This is not a code task.** Present the following proposed perk list to the player and get
explicit approval before starting Tasks 13-14.

**Universal perks (10)** — available to every class, one-time pick, non-stacking:

| id | Name | Effect |
|---|---|---|
| `might_boost` | Heavy Hands | +2 Might |
| `finesse_boost` | Quick Hands | +2 Finesse |
| `vigor_boost` | Iron Will | +2 Vigor |
| `focus_boost` | Clear Mind | +2 Focus |
| `grit_boost` | Stalwart | +2 Grit |
| `luck_boost` | Lucky Charm | +2 Luck |
| `deep_reserves` | Deep Reserves | +3 to whichever resource pool (Stamina or Mana) this character uses |
| `sharp_reflexes` | Sharp Reflexes | +5 flat Initiative |
| `thick_skin` | Thick Skin | −5% incoming damage, always |
| `battle_hardened` | Battle Hardened | −10% incoming DoT damage (stacks with Vigor and Warden's Deep Roots) |

**Class-flavored perks (7)** — one per class, amplifies that class's own L5 passive from Tasks
5-11 (keeps every perk self-contained within a method this plan already builds, rather than
touching unrelated shared code):

| Class | id | Name | Effect |
|---|---|---|---|
| Warrior | `deeper_grit` | Deeper Grit | Last Stand's bonus: +20% → +30% |
| Vanguard | `reinforced_bulwark` | Reinforced Bulwark | Bulwark's reduction: −15% → −25% |
| Skirmisher | `ruthless_opportunist` | Ruthless Opportunist | Opportunist's bonus: +15% → +25% |
| Chancer | `bigger_house_edge` | Bigger House Edge | House Edge's charge: +1 → +2 |
| Ranger | `deadeye` | Deadeye | Steady Aim's bonus: +10% → +20% |
| Seer | `overflowing_reservoir` | Overflowing Reservoir | Arcane Reservoir's bonus: +20% → +35% |
| Warden | `ancient_roots` | Ancient Roots | Deep Roots' reduction: −15% → −25% |

All magnitudes are `[ASSUMPTION]`. `deep_reserves`/`sharp_reflexes`/`thick_skin`/`battle_hardened`
are "bespoke" perks (checked by id at their specific hook, like a passive) since they aren't a
flat Stats-field bonus; the other 6 universal perks ARE flat Stats-field bonuses and apply
generically through `effective_stats()`.

**Do not proceed to Task 13 until the player has confirmed this table (as-is or with changes).**

---

## Task 13: Talent point data model + universal perks

**Files:**
- Create: `combat/resources/talent_perk_def.gd`
- Create: `combat/talent_perk_library.gd`
- Modify: `combat/resources/character_class.gd` (new `class_id` field)
- Modify: `combat/class_library.gd` (`c.class_id = &"<id>"` in all 7 branches; `build_combatant()`
  copy — see Step 3)
- Modify: `combat/combatant.gd` (`class_id`, `talent_perks`, `talent_points_earned()`,
  `talent_points_available()`, `talent_stat_bonuses()`, `pick_talent_perk()`,
  `unpick_talent_perk()`; extend `effective_stats()`, `apply_stats()`, `recompute_initiative()`,
  `incoming_damage_multiplier()`, `dot_damage_multiplier()`)
- Test: `tests/test_talent_perks.gd` (new)

**Interfaces:**
- Produces: `TalentPerkDef` (`id`, `display_name`, `description`, `stat_key: StringName = &""`,
  `stat_amount: int = 0`), `TalentPerkLibrary.universal_perks() -> Array[TalentPerkDef]`,
  `TalentPerkLibrary.class_perks(class_id: StringName) -> Array[TalentPerkDef]`,
  `TalentPerkLibrary.find_perk(id: StringName) -> TalentPerkDef`, `Combatant.class_id: StringName`,
  `Combatant.talent_perks: Array[StringName]`, `Combatant.talent_points_earned() -> int`,
  `Combatant.talent_points_available() -> int`, `Combatant.pick_talent_perk(id) -> bool`,
  `Combatant.unpick_talent_perk(id) -> bool`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_talent_perks.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Points earned/available across the level range (spec 2026-07-23 §5: clampi(level-4, 0, 6)).
	var c: Combatant = Combatant.new()
	c.level = 1
	_check(c.talent_points_earned() == 0, "L1: 0 talent points earned")
	c.level = 4
	_check(c.talent_points_earned() == 0, "L4: still 0 (points start at L5)")
	c.level = 5
	_check(c.talent_points_earned() == 1, "L5: 1 talent point earned")
	c.level = 10
	_check(c.talent_points_earned() == 6, "L10 (cap): 6 talent points earned")
	_check(c.talent_points_available() == 6, "L10, none spent: 6 available")

	# One-time-pick enforcement.
	_check(c.pick_talent_perk(&"vigor_boost"), "picking an unpicked perk succeeds")
	_check(c.talent_points_available() == 5, "one point spent")
	_check(not c.pick_talent_perk(&"vigor_boost"), "picking the SAME perk again is rejected")
	_check(c.talent_points_available() == 5, "rejected pick spends nothing")

	# Flat stat perk applies through effective_stats().
	_check(c.effective_stats().vigor == 2, "vigor_boost grants +2 Vigor via effective_stats()")

	# Unpick refunds the point (the panel is responsible for gating WHEN this is allowed).
	_check(c.unpick_talent_perk(&"vigor_boost"), "unpicking a picked perk succeeds")
	_check(c.talent_points_available() == 6, "unpicking refunds the point")
	_check(c.effective_stats().vigor == 0, "unpicking vigor_boost removes its bonus")
	_check(not c.unpick_talent_perk(&"vigor_boost"), "unpicking an unpicked perk is rejected")

	# Can't pick past the earned total.
	var poor_c: Combatant = Combatant.new()
	poor_c.level = 5
	_check(poor_c.pick_talent_perk(&"might_boost"), "1st pick at L5 succeeds")
	_check(not poor_c.pick_talent_perk(&"finesse_boost"), "2nd pick at L5 (only 1 point earned) is rejected")

	# Bespoke (non-stat) universal perks.
	var sr: Combatant = Combatant.new()
	sr.level = 5
	sr.pick_talent_perk(&"sharp_reflexes")
	sr.recompute_initiative()
	_check(sr.current_initiative == 5, "sharp_reflexes: +5 flat Initiative")

	var ts: Combatant = Combatant.new()
	ts.level = 5
	ts.pick_talent_perk(&"thick_skin")
	_check(is_equal_approx(ts.incoming_damage_multiplier(), 0.95), "thick_skin: -5% incoming damage")

	var bh: Combatant = Combatant.new()
	bh.level = 5
	bh.pick_talent_perk(&"battle_hardened")
	_check(is_equal_approx(bh.dot_damage_multiplier(), 0.9), "battle_hardened: -10% incoming DoT damage")

	var dr: Combatant = Combatant.new()
	dr.level = 5
	dr.base_max_stamina = 5
	dr.resource_pool = ResourcePool.new()
	dr.apply_stats()
	var before_stamina: int = dr.resource_pool.max_stamina
	dr.pick_talent_perk(&"deep_reserves")
	_check(dr.resource_pool.max_stamina == before_stamina + 3, "deep_reserves: +3 max Stamina")

	# TalentPerkLibrary shape.
	_check(TalentPerkLibrary.universal_perks().size() == 10, "10 universal perks authored")
	_check(TalentPerkLibrary.class_perks(&"warrior").size() == 1, "Warrior has 1 class-flavored perk")
	_check(TalentPerkLibrary.find_perk(&"deeper_grit") != null, "find_perk locates a class-flavored perk by id")
	_check(TalentPerkLibrary.find_perk(&"nonexistent") == null, "find_perk returns null for an unknown id")

	# class_id wiring.
	var wc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(wc.class_id == &"warrior", "CharacterClass.class_id set by ClassLibrary")
	var pc: Combatant = wc.build_combatant(true)
	_check(pc.class_id == &"warrior", "build_combatant() copies class_id")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_perks.gd`
Expected: FAIL / parse error — none of these members exist yet.

- [ ] **Step 3: Create `TalentPerkDef`**

Create `combat/resources/talent_perk_def.gd`:

```gdscript
class_name TalentPerkDef
extends Resource

## One talent-perk's data (spec 2026-07-23 §5). Mirrors AbilityDef's shape. A perk with a non-empty
## stat_key is a flat Stats-field bonus, applied generically by Combatant.talent_stat_bonuses() via
## effective_stats() — no bespoke code needed. A perk with an EMPTY stat_key is "bespoke": some
## other Combatant method checks `id in talent_perks` directly at its own hook point (mirrors how
## passive_ability_id dispatches, e.g. deep_reserves/sharp_reflexes/thick_skin/battle_hardened, or
## a class-flavored perk that amplifies that class's own passive).

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""

## One of &"might"/&"finesse"/&"vigor"/&"focus"/&"grit"/&"luck", or &"" for a bespoke perk.
@export var stat_key: StringName = &""
@export var stat_amount: int = 0
```

- [ ] **Step 4: Create `TalentPerkLibrary`**

Create `combat/talent_perk_library.gd`:

```gdscript
class_name TalentPerkLibrary
extends RefCounted

## Code registry of the 10 universal + 7 class-flavored talent perks (spec 2026-07-23 §5, content
## checkpoint approved). Mirrors ClassLibrary/EnemyLibrary: returns FRESH TalentPerkDefs each call.
## [ASSUMPTION] magnitudes — tune by playtest, same convention as every other numeric value in this
## project (CLAUDE.md §4).

static func _perk(id: StringName, name: String, desc: String, stat_key: StringName = &"", stat_amount: int = 0) -> TalentPerkDef:
	var p: TalentPerkDef = TalentPerkDef.new()
	p.id = id; p.display_name = name; p.description = desc
	p.stat_key = stat_key; p.stat_amount = stat_amount
	return p

static func universal_perks() -> Array[TalentPerkDef]:
	return [
		_perk(&"might_boost", "Heavy Hands", "+2 Might.", &"might", 2),
		_perk(&"finesse_boost", "Quick Hands", "+2 Finesse.", &"finesse", 2),
		_perk(&"vigor_boost", "Iron Will", "+2 Vigor.", &"vigor", 2),
		_perk(&"focus_boost", "Clear Mind", "+2 Focus.", &"focus", 2),
		_perk(&"grit_boost", "Stalwart", "+2 Grit.", &"grit", 2),
		_perk(&"luck_boost", "Lucky Charm", "+2 Luck.", &"luck", 2),
		_perk(&"deep_reserves", "Deep Reserves", "+3 to your Stamina or Mana pool (whichever you use)."),
		_perk(&"sharp_reflexes", "Sharp Reflexes", "+5 flat Initiative."),
		_perk(&"thick_skin", "Thick Skin", "-5% incoming damage, always."),
		_perk(&"battle_hardened", "Battle Hardened", "-10% incoming damage-over-time damage."),
	]

static func class_perks(class_id: StringName) -> Array[TalentPerkDef]:
	match class_id:
		&"warrior":
			return [_perk(&"deeper_grit", "Deeper Grit", "Last Stand's bonus: +20% -> +30%.")]
		&"vanguard":
			return [_perk(&"reinforced_bulwark", "Reinforced Bulwark", "Bulwark's reduction: -15% -> -25%.")]
		&"skirmisher":
			return [_perk(&"ruthless_opportunist", "Ruthless Opportunist", "Opportunist's bonus: +15% -> +25%.")]
		&"chancer":
			return [_perk(&"bigger_house_edge", "Bigger House Edge", "House Edge's charge: +1 -> +2.")]
		&"ranger":
			return [_perk(&"deadeye", "Deadeye", "Steady Aim's bonus: +10% -> +20%.")]
		&"seer":
			return [_perk(&"overflowing_reservoir", "Overflowing Reservoir", "Arcane Reservoir's bonus: +20% -> +35%.")]
		&"warden":
			return [_perk(&"ancient_roots", "Ancient Roots", "Deep Roots' reduction: -15% -> -25%.")]
		_:
			return []

## Searches the universal list, then every class's flavored list, for [param id]. Null if absent.
static func find_perk(id: StringName) -> TalentPerkDef:
	for p: TalentPerkDef in universal_perks():
		if p.id == id:
			return p
	for class_id: StringName in ClassLibrary.IDS:
		for p: TalentPerkDef in class_perks(class_id):
			if p.id == id:
				return p
	return null
```

- [ ] **Step 5: Add `class_id` to `CharacterClass`/`ClassLibrary`/`Combatant`**

In `combat/resources/character_class.gd`, add alongside `passive_ability_id`:

```gdscript
## This class's id in ClassLibrary.IDS (spec 2026-07-23 §5) — lets a built Combatant know which
## class-flavored talent perks it should see. Set by ClassLibrary.make(), copied by
## build_combatant() the same way every other class-identity field already is.
@export var class_id: StringName = &""
```

Also add to `build_combatant()`, alongside `c.passive_ability_id = passive_ability_id`:

```gdscript
	c.class_id = class_id
```

In `combat/class_library.gd`, add `c.class_id = &"warrior"` (etc., one per branch, matching each
`match id:` arm) immediately after each branch's `var c: CharacterClass = CharacterClass.new()`
line — 7 one-line additions, one per class.

In `combat/combatant.gd`, add alongside `passive_ability_id`:

```gdscript
## This combatant's class id (spec 2026-07-23 §5) — which class-flavored talent perks it can pick
## from (TalentPerkLibrary.class_perks(class_id)). Empty for enemies/target dummies.
var class_id: StringName = &""
```

- [ ] **Step 6: Add the talent-points + pick/unpick surface to `Combatant`**

In `combat/combatant.gd`, add alongside `extra_abilities`:

```gdscript
## Ids of talent perks this combatant has picked, in pick order (spec 2026-07-23 §5). One-time-pick
## per id — picking the same id twice is rejected by pick_talent_perk().
var talent_perks: Array[StringName] = []

## Total talent points earned so far: one per level from 5 to MAX_LEVEL (6 at the cap). Derived,
## not stored — mirrors this codebase's existing preference (e.g. current_initiative).
func talent_points_earned() -> int:
	return clampi(level - 4, 0, 6)

## Earned minus spent. Never negative (picks are rejected once this hits 0).
func talent_points_available() -> int:
	return talent_points_earned() - talent_perks.size()

## The Stats bonus contributed by every picked FLAT-STAT perk (a perk with a non-empty stat_key).
## Bespoke (non-stat) perks are NOT represented here — they're checked by id at their own hook.
func talent_stat_bonuses() -> Stats:
	var s: Stats = Stats.new()
	for id: StringName in talent_perks:
		var def: TalentPerkDef = TalentPerkLibrary.find_perk(id)
		if def == null or def.stat_key == &"":
			continue
		match def.stat_key:
			&"might": s.might += def.stat_amount
			&"finesse": s.finesse += def.stat_amount
			&"vigor": s.vigor += def.stat_amount
			&"focus": s.focus += def.stat_amount
			&"grit": s.grit += def.stat_amount
			&"luck": s.luck += def.stat_amount
	return s

## Spends one unspent talent point on perk [param id]. Rejects a perk already picked (one-time-pick)
## or if no points remain. Recomputes derived stats/initiative so the effect is immediate.
func pick_talent_perk(id: StringName) -> bool:
	if id in talent_perks or talent_points_available() <= 0:
		return false
	talent_perks.append(id)
	apply_stats()
	recompute_initiative()
	return true

## Refunds the point spent on [param id]. The CALLER (TalentMenuPanel) is responsible for only
## exposing this when respec is allowed (town-only, spec §2) — this method itself has no
## safe-zone awareness, mirroring how equip_gear/unequip_gear carry no such policy either.
func unpick_talent_perk(id: StringName) -> bool:
	if id not in talent_perks:
		return false
	talent_perks.erase(id)
	apply_stats()
	recompute_initiative()
	return true
```

- [ ] **Step 7: Wire flat-stat perks into `effective_stats()`**

In `combat/combatant.gd`'s `effective_stats()`, change:

```gdscript
func effective_stats() -> Stats:
	var s: Stats = Stats.new()
	if base_stats != null:
		s = s.plus(base_stats)
	for g: Gear in gear:
		if g != null:
			s = s.plus(g.stat_bonuses)
	return s
```

to:

```gdscript
func effective_stats() -> Stats:
	var s: Stats = Stats.new()
	if base_stats != null:
		s = s.plus(base_stats)
	for g: Gear in gear:
		if g != null:
			s = s.plus(g.stat_bonuses)
	s = s.plus(talent_stat_bonuses())
	return s
```

- [ ] **Step 8: Wire the 4 bespoke universal perks**

In `combat/combatant.gd`'s `recompute_initiative()`, change:

```gdscript
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.effective_magnitude()
	current_initiative = base_initiative + int(roundf(total))
```

to:

```gdscript
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.effective_magnitude()
	if &"sharp_reflexes" in talent_perks:
		total += 5.0
	current_initiative = base_initiative + int(roundf(total))
```

In `incoming_damage_multiplier()` (already modified by Task 3 to include
`total *= passive_incoming_multiplier()`), add one more line before `return total`:

```gdscript
	if &"thick_skin" in talent_perks:
		total *= 0.95
```

In `dot_damage_multiplier()` (already modified by Task 3), change:

```gdscript
func dot_damage_multiplier() -> float:
	var base: float = clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
	return base * passive_dot_damage_multiplier()
```

to:

```gdscript
func dot_damage_multiplier() -> float:
	var base: float = clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
	var result: float = base * passive_dot_damage_multiplier()
	if &"battle_hardened" in talent_perks:
		result *= 0.9
	return result
```

In `apply_stats()`, immediately after the existing `if resource_pool != null:` block's Focus-regen
lines (right before the `if bonus_meter != null:` block), add:

```gdscript
	if resource_pool != null and &"deep_reserves" in talent_perks:
		if resource_pool.max_stamina > 0:
			resource_pool.max_stamina += 3
			resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
		if resource_pool.max_mana > 0:
			resource_pool.max_mana += 3
			resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
```

- [ ] **Step 9: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_perks.gd`
Expected: all lines print `ok `.

- [ ] **Step 10: Run the full suite**

Run every test file under `tests/`. `effective_stats()`/`apply_stats()`/`recompute_initiative()`/
`incoming_damage_multiplier()`/`dot_damage_multiplier()` all changed — every pre-existing
`Combatant` has an empty `talent_perks`, so every new term is a no-op (`+0`, `*1.0`) for them;
confirm that's actually true by a clean full-suite run.

- [ ] **Step 11: Commit**

```bash
git add combat/resources/talent_perk_def.gd combat/talent_perk_library.gd combat/resources/character_class.gd combat/class_library.gd combat/combatant.gd tests/test_talent_perks.gd
git commit -m "feat(talents): talent-point data model, pick/unpick, and the 10 universal perks"
```

---

## Task 14: Class-flavored perks (amplify each class's own passive)

**Files:**
- Modify: `combat/combatant.gd` (the 4 passive match arms that get a talent-perk amplification
  check: `passive_outgoing_multiplier()` for Last Stand/Opportunist/Steady Aim,
  `passive_incoming_multiplier()` for Bulwark, `passive_dot_damage_multiplier()` for Deep Roots,
  `passive_max_mana_multiplier()` for Arcane Reservoir, `passive_on_payline_scored()` for House
  Edge)
- Test: `tests/test_talent_class_perks.gd` (new)

**Interfaces:**
- Consumes: `Combatant.talent_perks` (Task 13), the 7 passive match arms (Tasks 5-11),
  `TalentPerkLibrary.class_perks()` (Task 13, content already authored — this task only wires the
  numbers it already lists into the passive methods).

- [ ] **Step 1: Write the failing test**

Create `tests/test_talent_class_perks.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var warrior: Combatant = Combatant.new()
	warrior.passive_ability_id = &"last_stand"
	warrior.level = 5
	warrior.max_hp = 100
	warrior.hp = 30
	_check(warrior.passive_outgoing_multiplier() == 1.2, "Last Stand alone: +20%")
	warrior.pick_talent_perk(&"deeper_grit")
	_check(warrior.passive_outgoing_multiplier() == 1.3, "Last Stand + Deeper Grit: +30%")

	var vanguard: Combatant = Combatant.new()
	vanguard.passive_ability_id = &"bulwark"
	vanguard.level = 5
	vanguard.max_hp = 100
	vanguard.hp = 100
	vanguard.pick_talent_perk(&"reinforced_bulwark")
	_check(vanguard.passive_incoming_multiplier() == 0.75, "Bulwark + Reinforced Bulwark: -25%")

	var skirmisher: Combatant = Combatant.new()
	skirmisher.passive_ability_id = &"opportunist"
	skirmisher.level = 5
	skirmisher.pick_talent_perk(&"ruthless_opportunist")
	var defender: Combatant = Combatant.new()
	defender.attach_effect(EffectLibrary.make(&"slow"))
	_check(skirmisher.passive_outgoing_multiplier(defender) == 1.25, "Opportunist + Ruthless Opportunist: +25%")

	var chancer: Combatant = Combatant.new()
	chancer.passive_ability_id = &"house_edge"
	chancer.level = 5
	chancer.bonus_meter = BonusMeter.new()
	chancer.bonus_meter.cap = 15
	chancer.pick_talent_perk(&"bigger_house_edge")
	var before: int = chancer.bonus_meter.value
	chancer.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(chancer.bonus_meter.value == before + 2, "House Edge + Bigger House Edge: +2 instead of +1")

	var ranger: Combatant = Combatant.new()
	ranger.passive_ability_id = &"steady_aim"
	ranger.level = 5
	ranger.pick_talent_perk(&"deadeye")
	var marked: Combatant = Combatant.new()
	marked.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(ranger.passive_outgoing_multiplier(marked) == 1.20, "Steady Aim + Deadeye: +20%")

	var seer: Combatant = Combatant.new()
	seer.passive_ability_id = &"arcane_reservoir"
	seer.level = 5
	seer.pick_talent_perk(&"overflowing_reservoir")
	_check(is_equal_approx(seer.passive_max_mana_multiplier(), 1.35), "Arcane Reservoir + Overflowing Reservoir: +35%")

	var warden: Combatant = Combatant.new()
	warden.passive_ability_id = &"deep_roots"
	warden.level = 5
	warden.pick_talent_perk(&"ancient_roots")
	_check(is_equal_approx(warden.passive_dot_damage_multiplier(), 0.75), "Deep Roots + Ancient Roots: -25%")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_class_perks.gd`
Expected: FAIL (the amplification checks don't exist yet — every assertion above sees the BASE
magnitude, not the amplified one).

- [ ] **Step 3: Implement — amplify each of the 7 passives**

In `combat/combatant.gd`'s `passive_outgoing_multiplier()`, change the 3 relevant arms:

```gdscript
		&"last_stand":
			var bonus: float = 0.30 if &"deeper_grit" in talent_perks else 0.20
			return 1.0 + bonus if (float(hp) / float(maxi(max_hp, 1))) <= 0.30 else 1.0
		&"opportunist":
			if defender == null:
				return 1.0
			var bonus: float = 0.25 if &"ruthless_opportunist" in talent_perks else 0.15
			return 1.0 + bonus if (defender.has_effect(&"slow") or defender.has_effect(&"rooted") or defender.stunned_last_turn) else 1.0
		&"steady_aim":
			var bonus: float = 0.20 if &"deadeye" in talent_perks else 0.10
			return 1.0 + bonus if (defender != null and defender.has_effect(&"hunters_mark")) else 1.0
```

In `passive_incoming_multiplier()`, change the `&"bulwark"` arm:

```gdscript
		&"bulwark":
			var reduction: float = 0.25 if &"reinforced_bulwark" in talent_perks else 0.15
			return 1.0 - reduction if (float(hp) / float(maxi(max_hp, 1))) > 0.50 else 1.0
```

In `passive_dot_damage_multiplier()`, change the `&"deep_roots"` arm:

```gdscript
		&"deep_roots":
			return 0.75 if &"ancient_roots" in talent_perks else 0.85
```

In `passive_max_mana_multiplier()`, change the `&"arcane_reservoir"` arm:

```gdscript
		&"arcane_reservoir":
			return 1.35 if &"overflowing_reservoir" in talent_perks else 1.2
```

In `passive_on_payline_scored()`, change the `&"house_edge"` arm:

```gdscript
		&"house_edge":
			if bonus_meter != null:
				bonus_meter.add_flat(2 if &"bigger_house_edge" in talent_perks else 1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_class_perks.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Run the full suite**

Run every test file under `tests/`, including all 7 `test_passive_*.gd` files from Tasks 5-11 —
confirm the base (unamplified) magnitudes are unaffected for a `Combatant` with no matching perk
picked (every pre-existing passive test has an empty `talent_perks`).

- [ ] **Step 6: Commit**

```bash
git add combat/combatant.gd tests/test_talent_class_perks.gd
git commit -m "feat(talents): 7 class-flavored perks amplify their class's own L5 passive"
```

---

## Task 15: `TalentMenuPanel` UI

**Files:**
- Create: `combat/ui/talent_menu_panel.gd`
- Test: `tests/test_talent_menu_panel.gd` (new)

**Interfaces:**
- Consumes: `Combatant.talent_perks/talent_points_earned()/talent_points_available()/
  pick_talent_perk()/unpick_talent_perk()` (Task 13), `TalentPerkLibrary.universal_perks()/
  class_perks()` (Task 13).
- Produces: `TalentMenuPanel.open_for(c: Combatant, respec_available: bool) -> void`,
  `picked_ids_for_test() -> Array[StringName]`, `available_ids_for_test() -> Array[StringName]`,
  `press_pick_for_test(id) -> void`, `press_unpick_for_test(id) -> void`,
  `press_close_for_test() -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_talent_menu_panel.gd`:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.class_id = &"warrior"
	c.level = 5

	var panel: TalentMenuPanel = TalentMenuPanel.new()
	panel.open_for(c, true)
	_check(panel.picked_ids_for_test().is_empty(), "no perks picked yet")
	_check(panel.available_ids_for_test().size() == 11, "pool = 10 universal + Warrior's 1 flavored perk")

	panel.press_pick_for_test(&"vigor_boost")
	_check(&"vigor_boost" in c.talent_perks, "pressing a Pick row actually picks it")
	panel.open_for(c, true)  # rows are rebuilt fresh on every open, mirrors AbilityMenuPanel
	_check(panel.picked_ids_for_test() == [&"vigor_boost"], "picked list now shows vigor_boost")
	_check(not (&"vigor_boost" in panel.available_ids_for_test()), "picked perk drops out of the available list")

	panel.press_unpick_for_test(&"vigor_boost")
	_check(not (&"vigor_boost" in c.talent_perks), "pressing Unpick (respec_available=true) actually unpicks it")

	# Respec gate: town-only (spec §2).
	c.pick_talent_perk(&"vigor_boost")
	panel.open_for(c, false)  # overworld/dungeon: view-only
	panel.press_unpick_for_test(&"vigor_boost")
	_check(&"vigor_boost" in c.talent_perks, "Unpick is a no-op when respec_available is false")

	# No points left: Pick rows should refuse.
	var poor_c: Combatant = Combatant.new()
	poor_c.class_id = &"warrior"
	poor_c.level = 4  # 0 points earned
	var panel2: TalentMenuPanel = TalentMenuPanel.new()
	panel2.open_for(poor_c, true)
	panel2.press_pick_for_test(&"vigor_boost")
	_check(poor_c.talent_perks.is_empty(), "Pick is a no-op with 0 points available")
	panel2.press_close_for_test()
	_check(not panel2.visible, "close button hides the panel")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_menu_panel.gd`
Expected: FAIL / parse error — `TalentMenuPanel` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `combat/ui/talent_menu_panel.gd`:

```gdscript
class_name TalentMenuPanel
extends Panel

## Non-modal floating talent menu (spec 2026-07-23 §6): one row per PICKED perk (with an Unpick
## action) followed by one row per AVAILABLE perk in this character's pool (universal +
## TalentPerkLibrary.class_perks(class_id)) not already picked, with a Pick action. Mirrors
## AbilityMenuPanel's shape (non-modal float, rebuilt fresh on every open). Respec (Unpick) is
## disabled whenever [param respec_available] is false — the caller (town/overworld/dungeon scene)
## decides that, mirroring InventoryMenuPanel's existing vault_available convention.

const PAD: float = 12.0
const TITLE_H: float = 26.0
const ROW_H: float = 54.0
const BTN_W: float = 220.0
const INFO_W: float = 420.0
const ACTION_W: float = 90.0
const CLOSE_SIZE: float = 28.0
const PANEL_W: float = PAD * 2.0 + BTN_W + 12.0 + INFO_W + 12.0 + ACTION_W

var _combatant: Combatant
var _respec_available: bool = true
var _picked_ids: Array[StringName] = []
var _available_ids: Array[StringName] = []
var _action_buttons: Dictionary = {}  # StringName -> Button
var _close_button: Button

func open_for(c: Combatant, respec_available: bool) -> void:
	for child in get_children():
		child.queue_free()
	_action_buttons.clear()
	_combatant = c
	_respec_available = respec_available
	_picked_ids.clear()
	_available_ids.clear()
	if c == null:
		return
	_picked_ids = c.talent_perks.duplicate()
	var pool: Array[TalentPerkDef] = TalentPerkLibrary.universal_perks()
	pool.append_array(TalentPerkLibrary.class_perks(c.class_id))
	for def: TalentPerkDef in pool:
		if not (def.id in _picked_ids):
			_available_ids.append(def.id)

	var title := Label.new()
	title.text = "Talents — %d/%d points spent%s" % [
		c.talent_perks.size(), c.talent_points_earned(),
		"" if respec_available else "  (view only — visit a town to respec)"
	]
	title.position = Vector2(PAD, PAD - 2.0)
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.position = Vector2(PANEL_W - PAD - CLOSE_SIZE, PAD - 4.0)
	_close_button.custom_minimum_size = Vector2(CLOSE_SIZE, CLOSE_SIZE)
	_close_button.pressed.connect(func() -> void: hide())
	add_child(_close_button)

	var top: float = PAD + TITLE_H
	var row_i: int = 0
	for id: StringName in _picked_ids:
		_build_row(id, top + float(row_i) * ROW_H, true)
		row_i += 1
	for id: StringName in _available_ids:
		_build_row(id, top + float(row_i) * ROW_H, false)
		row_i += 1

	custom_minimum_size = Vector2(PANEL_W, top + float(row_i) * ROW_H + PAD)
	size = custom_minimum_size
	show()

func _build_row(id: StringName, y: float, picked: bool) -> void:
	var def: TalentPerkDef = TalentPerkLibrary.find_perk(id)
	if def == null:
		return

	var name_label := Label.new()
	name_label.text = def.display_name
	name_label.position = Vector2(PAD, y)
	name_label.custom_minimum_size = Vector2(BTN_W, ROW_H - 10.0)
	add_child(name_label)

	var info := Label.new()
	info.text = def.description
	info.position = Vector2(PAD + BTN_W + 12.0, y)
	info.custom_minimum_size = Vector2(INFO_W, ROW_H - 10.0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	add_child(info)

	var action := Button.new()
	action.position = Vector2(PAD + BTN_W + 12.0 + INFO_W + 12.0, y)
	action.custom_minimum_size = Vector2(ACTION_W, ROW_H - 10.0)
	if picked:
		action.text = "Unpick"
		action.disabled = not _respec_available
		action.pressed.connect(func() -> void:
			_combatant.unpick_talent_perk(id)
			open_for(_combatant, _respec_available))
	else:
		action.text = "Pick"
		action.disabled = _combatant.talent_points_available() <= 0
		action.pressed.connect(func() -> void:
			_combatant.pick_talent_perk(id)
			open_for(_combatant, _respec_available))
	add_child(action)
	_action_buttons[id] = action

func picked_ids_for_test() -> Array[StringName]:
	return _picked_ids.duplicate()

func available_ids_for_test() -> Array[StringName]:
	return _available_ids.duplicate()

func press_pick_for_test(id: StringName) -> void:
	var btn: Button = _action_buttons.get(id, null)
	if btn != null and not btn.disabled:
		btn.pressed.emit()

func press_unpick_for_test(id: StringName) -> void:
	var btn: Button = _action_buttons.get(id, null)
	if btn != null and not btn.disabled:
		btn.pressed.emit()

func press_close_for_test() -> void:
	if _close_button != null:
		_close_button.pressed.emit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_talent_menu_panel.gd`
Expected: all lines print `ok `.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/talent_menu_panel.gd tests/test_talent_menu_panel.gd
git commit -m "feat(talents): TalentMenuPanel — pick/unpick perks, town-only respec gate"
```

---

## Task 16: Input action + world-scene wiring

**Files:**
- Modify: `project.godot` (new `toggle_talents` input action)
- Modify: `world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd`
- Test: `tests/test_town_demo_talents.gd`, `tests/test_overworld_demo_talents.gd`,
  `tests/test_dungeon_demo_talents.gd` (new, one per scene, mirroring the existing
  `test_town_demo_inventory.gd`-style real-scene test pattern)

**Interfaces:**
- Consumes: `TalentMenuPanel.open_for(c, respec_available)` (Task 15).

- [ ] **Step 1: Add the input action**

In `project.godot`, immediately after the existing `toggle_event_log` block (ends with a `}` on
its own line), add:

```
toggle_talents={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":78,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

(Physical keycode 78 = `N`, confirmed free against every other bound action in this file.)

- [ ] **Step 2: Wire `town_demo.gd`**

Add a field alongside the existing `var _inventory_panel: InventoryMenuPanel` (line 31):

```gdscript
var _talent_panel: TalentMenuPanel
```

Immediately after the existing inventory-panel construction (`town_demo.gd:310-315`), add:

```gdscript
	_talent_panel = TalentMenuPanel.new()
	_talent_panel.position = Vector2(140, 60)
	_talent_panel.hide()
	_ui_layer.add_child(_talent_panel)
```

Add a new toggle function, mirroring `_toggle_stats()` (`town_demo.gd:600-608`) but for the new
panel, and add `_talent_panel.visible` to the two existing toggles' guard conditions so the two
panels never both show at once:

```gdscript
func _toggle_talents() -> void:
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open() or _inventory_panel.visible:
		return
	if _talent_panel.visible:
		_talent_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_talent_panel.open_for(_pc_combatant, true)   # town = safe zone, respec allowed
		_pc.set_movement_paused(true)
```

Change the existing `_toggle_inventory()`/`_toggle_stats()` guard lines (both currently read
`if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or
_vendor_prompt_panel.is_open() or _shop_panel.is_open():`) to also check
`or _talent_panel.visible` at the end of that same condition, in both functions.

In `_unhandled_input()` (`town_demo.gd:610-624`), add a new branch alongside the existing
`toggle_stats` one:

```gdscript
	if event.is_action_pressed("toggle_talents"):
		_toggle_talents()
		return
```

and change the existing `if _inventory_panel.visible: return` guard (line 620, right before the
interact-key handling) to `if _inventory_panel.visible or _talent_panel.visible: return`.

- [ ] **Step 3: Wire `overworld_demo.gd`**

Same shape as Step 2, adapted to this scene's guard set (`_random_encounter_panel` instead of the
town's dialogue/board/vendor/shop panels), `ui`/`_pc_combatant` names, and `respec_available =
false` (overworld is not a safe zone):

```gdscript
var _talent_panel: TalentMenuPanel
```

After the existing inventory-panel construction (`overworld_demo.gd:274-278`):

```gdscript
	_talent_panel = TalentMenuPanel.new()
	_talent_panel.position = Vector2(140, 60)
	_talent_panel.hide()
	ui.add_child(_talent_panel)
```

New toggle function:

```gdscript
func _toggle_talents() -> void:
	if _random_encounter_panel.is_open() or _inventory_panel.visible:
		return
	if _talent_panel.visible:
		_talent_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_talent_panel.open_for(_pc_combatant, false)   # overworld = not a safe zone, view-only
		_pc.set_movement_paused(true)
```

Add `or _talent_panel.visible` to `_toggle_inventory()`/`_toggle_stats()`'s existing `if
_random_encounter_panel.is_open(): return` guards (`overworld_demo.gd:548`/`561`) — i.e. change
those to `if _random_encounter_panel.is_open() or _talent_panel.visible: return`.

In `_unhandled_input()` (`overworld_demo.gd:607-619`), add the same `toggle_talents` branch as
Step 2, and change line 617's `if _inventory_panel.visible or _random_encounter_panel.is_open():
return` to also include `or _talent_panel.visible`.

In `_process()` (`overworld_demo.gd:570-596`), change line 573's `if _inventory_panel.visible or
_dialogue_box.is_open() or _random_encounter_panel.is_open():` to also include `or
_talent_panel.visible`, so the interact-prompt/highlight logic pauses while the talent panel is
open (mirrors how it already pauses for the inventory panel).

- [ ] **Step 4: Wire `dungeon_demo.gd`**

Same shape, this scene's simpler guard set (only `_inventory_panel.visible`), `respec_available =
false` (dungeon is not a safe zone):

```gdscript
var _talent_panel: TalentMenuPanel
```

After the existing inventory-panel construction (`dungeon_demo.gd:272-276`):

```gdscript
	_talent_panel = TalentMenuPanel.new()
	_talent_panel.position = Vector2(140, 60)
	_talent_panel.hide()
	ui.add_child(_talent_panel)
```

New toggle function:

```gdscript
func _toggle_talents() -> void:
	if _inventory_panel.visible:
		return
	if _talent_panel.visible:
		_talent_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_talent_panel.open_for(_pc_combatant, false)   # dungeon = not a safe zone, view-only
		_pc.set_movement_paused(true)
```

In `_toggle_inventory()`/`_toggle_stats()` (`dungeon_demo.gd:473-487`), change both `if
_inventory_panel.visible:` early-return guards to `if _inventory_panel.visible or
_talent_panel.visible:` (they currently only check `_inventory_panel.visible` before deciding to
close vs. open — this stops either panel opening on top of the other, same as the other 2 scenes).

In `_unhandled_input()` (`dungeon_demo.gd:455-472`), add the `toggle_talents` branch (same as
Steps 2-3), and change line 465's `if _inventory_panel.visible: return` to `if
_inventory_panel.visible or _talent_panel.visible: return`.

In `_process()` (`dungeon_demo.gd:421-444`), change line 424's `if _inventory_panel.visible:` to
`if _inventory_panel.visible or _talent_panel.visible:`.

- [ ] **Step 5: Write the 3 scene-level tests**

First, add a small test hook to `TalentMenuPanel` (Task 15's file) so these 3 tests can confirm
the respec gate without new plumbing:

```gdscript
func respec_available_for_test() -> bool:
	return _respec_available
```

Create `tests/test_town_demo_talents.gd`, mirroring `tests/test_town_demo_inventory.gd`'s exact
established pattern (`_process(_delta) -> bool` with a frame counter, `root.add_child()`, not
`await`, and `PCController.movement_paused_for_test()` — read that file's `_init()`/`_process()`
before writing this, its structure is the template):

```gdscript
extends SceneTree

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		_check(town._talent_panel != null, "TalentMenuPanel is built")
		_check(not town._talent_panel.visible, "talent panel starts closed")
		town._toggle_talents()
		_check(town._talent_panel.visible, "toggle_talents opens the panel")
		_check(town._pc.movement_paused_for_test(), "opening the talent panel pauses PC movement")
		_check(town._talent_panel.respec_available_for_test(), "town passes respec_available = true")
		town._toggle_talents()
		_check(not town._talent_panel.visible, "toggling again closes the panel")
		_check(not town._pc.movement_paused_for_test(), "closing the talent panel resumes PC movement")
		quit()
		return true
	return false
```

Create `tests/test_overworld_demo_talents.gd` and `tests/test_dungeon_demo_talents.gd`
identically, loading `res://world/overworld_demo.tscn` / `res://world/dungeon_demo.tscn`, typing
the local as `OverworldDemo`/`DungeonDemo`, calling `_toggle_talents()` the same way, and asserting
`respec_available_for_test()` is **false** for both (overworld/dungeon are not safe zones).

- [ ] **Step 6: Run all 3 new tests + the full suite**

Run each of the 3 new test files individually, then the full `tests/` sweep (this task touches 3
scene files' `_unhandled_input`/`_process`/toggle functions — confirm no regression to dialogue/
board/shop/random-encounter panel interactions in any of the 3 scenes).

- [ ] **Step 7: Commit**

```bash
git add project.godot world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd combat/ui/talent_menu_panel.gd tests/test_town_demo_talents.gd tests/test_overworld_demo_talents.gd tests/test_dungeon_demo_talents.gd
git commit -m "feat(talents): wire the Talents panel into town/overworld/dungeon via the N key"
```

---

## Task 17: Final whole-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the complete headless test suite**

Run every `tests/test_*.gd` file (this project's standing "Verified-by-machine" convention,
CLAUDE.md §8). Confirm a clean sweep — any failure is a real regression from this plan and must be
fixed before this feature is considered shipped; any SIGSEGV must be confirmed a known
teardown-only flake by an individual clean retry, not waved off on sight.

- [ ] **Step 2: Confirm the level cap end-to-end**

Using the ENDGAME toggle (now L10) in `combat.tscn`, confirm all 7 classes: show 4 unlocked
extra-ability rows (base + 3, per Task 2) in the Abilities menu, show their L5 passive is active
(spot-check via the relevant `test_passive_*.gd` behavior, not a manual play session — this step
is a machine check, not the human playtest), and expose 6 available talent points with the full
17-perk pool (10 universal + their class's 1 flavored perk) in the Talents panel.

- [ ] **Step 3: Update CLAUDE.md's status log**

Add a `SHIPPED` entry to `CLAUDE.md` §8 following this project's existing convention (see any
prior entry, e.g. the Old Well rest-point entry, for the expected shape): what shipped, which
spec/plan it came from, test-suite count before/after, and an explicit "a human has not yet
playtested this live" note — per this project's own §5 hard ceiling, machine verification never
substitutes for the player's own judgment on whether the abilities/passives/talents actually feel
right.

- [ ] **Step 4: Final commit**

```bash
git add CLAUDE.md
git commit -m "docs: log the ability/talent redesign ship in CLAUDE.md status"
```

