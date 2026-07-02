# Ability Menu UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the combat scene a single "Abilities" button opening a floating menu panel where the
player stages any one unlocked ability (base L1 + unlocked L5/L7/L9), replacing the old single
base-ability button — the missing presentation layer for the 21 new abilities.

**Architecture:** Pure UI over the EXISTING, test-green model: `MainPhasePlan.toggle_ability()` /
`toggle_extra_ability(id)` / `can_stage_extra_ability(id)` and `Combatant.unlocked_extra_abilities()`
/ `cooldowns` already handle staging, mutual exclusivity, preview, commit, and cooldowns — **no model
files are modified.** Three new units: `AbilityCatalog` (static id → name/description data),
`AbilityMenuPanel` (non-modal floating panel, `TypeChartPanel` precedent), and `combat.gd` wiring
(button + handlers). Spec: `docs/superpowers/specs/2026-07-02-ability-menu-ui-design.md`.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree` tests (no framework), static typing.

## Global Constraints

- GDScript only, no C# (CLAUDE.md §2).
- Static typing on new vars/functions (CLAUDE.md §2).
- Signals: snake_case, past-tense, no `on_` prefix on the signal itself; handlers `_on_<emitter>_<signal>` (CLAUDE.md §2).
- Staged-green is `Color(0.6, 1.0, 0.6)`; locked-grey is `Color(0.5, 0.5, 0.5)` (existing combat.gd conventions).
- Locked (below-unlock-level) abilities are HIDDEN, never greyed (player-locked, spec §Player-locked #1).
- The Ultimate button is untouched (spec §Player-locked #3).
- Costs/cooldowns are read LIVE from `AbilityDef`/plan data — never duplicated into `AbilityCatalog` (spec §4).
- Do not modify `main_phase_plan.gd`, `combatant.gd`, or any `combat/resources/` file.
- Every existing test must stay green. Single test:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
- Full regression (PowerShell, from the project root `bunnies/`):
  ```powershell
  $fails = @(); Get-ChildItem tests\test_*.gd | ForEach-Object { $out = & Godot_v4.6.3-stable_win64_console.exe --headless --path . --script ("res://tests/" + $_.Name); if ($out -match "FAIL") { $fails += $_.Name } }; if ($fails.Count -eq 0) { "ALL GREEN" } else { $fails }
  ```
  Expected: `ALL GREEN`.

## File Structure

New files:
- `combat/ui/ability_catalog.gd` — `AbilityCatalog`: static id → display name + description (all 28 abilities).
- `combat/ui/ability_menu_panel.gd` — `AbilityMenuPanel`: the floating menu; also owns the pure
  `row_state()` / `cost_text()` / `cooldown_text()` statics (unit-testable without a scene).
- `tests/test_ability_catalog.gd`, `tests/test_ability_menu_state.gd`, `tests/test_ability_menu_panel.gd`.

Modified files:
- `combat/combat.gd` — `_splice_button` → `_abilities_button` (opens the menu), new handlers
  `_on_abilities_pressed` / `_on_ability_menu_ability_pressed`, `_refresh_main1_preview` button block
  rewrite, close-on-SPIN/turn-change, `_ability_label`/`_ability_tooltip` deleted (dead),
  `_ability_name` migrated to the catalog.
- `CLAUDE.md` §8 — status update (final task).

---

## Task 1: `AbilityCatalog`

**Files:**
- Create: `combat/ui/ability_catalog.gd`
- Test: `tests/test_ability_catalog.gd`

**Interfaces:**
- Produces: `AbilityCatalog.display_name(id: StringName) -> String`,
  `AbilityCatalog.description(id: StringName) -> String`. Both return `""` for unknown ids.
  Task 3 renders these into rows; Task 4's `_refresh_main1_preview` and `_ability_name` read
  `display_name`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_catalog.gd`:

```gdscript
extends SceneTree

## Catalog completeness: every ability id any class ships (base ability_id + all extra_abilities)
## must have a non-empty display name AND description — catches a forgotten catalog entry whenever
## a future ability is added (spec 2026-07-02 §4).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var class_ids: Array[StringName] = [&"warrior", &"vanguard", &"skirmisher", &"chancer", &"ranger", &"seer", &"warden"]
	var seen: int = 0
	for cid: StringName in class_ids:
		var cc: CharacterClass = ClassLibrary.make(cid)
		var ids: Array[StringName] = [cc.ability_id]
		for def: AbilityDef in cc.extra_abilities:
			ids.append(def.id)
		for id: StringName in ids:
			seen += 1
			_check(AbilityCatalog.display_name(id) != "", "%s/%s: display_name non-empty" % [cid, id])
			_check(AbilityCatalog.description(id) != "", "%s/%s: description non-empty" % [cid, id])
	_check(seen == 28, "roster carries 28 ability ids (7 base + 21 extra), saw %d" % seen)
	_check(AbilityCatalog.display_name(&"nope") == "", "unknown id -> empty name")
	_check(AbilityCatalog.description(&"nope") == "", "unknown id -> empty description")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_catalog.gd`
Expected: FAIL to load — `AbilityCatalog` does not exist (parse error naming the missing identifier).

- [ ] **Step 3: Write minimal implementation**

Create `combat/ui/ability_catalog.gd` (precedent: `RoleVisuals`/`TypeVisuals` static helpers):

```gdscript
class_name AbilityCatalog

## Static id → player-facing name + description for ALL 28 abilities (7 base + 21 extra), the one
## source of truth for ability copy (spec 2026-07-02 §4). Costs and cooldowns are NOT here — the
## menu reads them live from AbilityDef/MainPhasePlan so they can never drift from combat math.
## Descriptions state each ability's numbers; those magnitudes are [ASSUMPTION] balance placeholders
## (CLAUDE.md §4) — when one is retuned post-playtest, update its description here too (the
## test_ability_catalog completeness suite is the greppable reminder hook).

static func display_name(id: StringName) -> String:
	match id:
		# --- base (L1) abilities ---
		&"rend": return "Rend"
		&"heft": return "Heft"
		&"flurry": return "Flurry"
		&"reroll": return "Re-roll"
		&"hunters_mark": return "Hunter's Mark"
		&"select_fate": return "Select your Fate!"
		&"rallying_cry": return "Rallying Cry"
		# --- Warrior ---
		&"sundering_strike": return "Sundering Strike"
		&"heroic_guard": return "Heroic Guard"
		&"second_wind": return "Second Wind"
		# --- Vanguard ---
		&"bloodwrath": return "Bloodwrath"
		&"quake_slam": return "Quake Slam"
		&"mountain_stance": return "Mountain Stance"
		# --- Skirmisher ---
		&"feint_riposte": return "Feint & Riposte"
		&"quickstep": return "Quickstep"
		&"riposte_storm": return "Riposte Storm"
		# --- Chancer ---
		&"loaded_dice": return "Loaded Dice"
		&"jinx_the_odds": return "Jinx the Odds"
		&"double_or_nothing": return "Double or Nothing"
		# --- Ranger ---
		&"aimed_shot": return "Aimed Shot"
		&"snare_trap": return "Snare Trap"
		&"crippling_shot": return "Crippling Shot"
		# --- Seer ---
		&"hex": return "Hex"
		&"foresight": return "Foresight"
		&"mana_surge": return "Mana Surge"
		# --- Warden ---
		&"entangle": return "Entangle"
		&"regrowth": return "Regrowth"
		&"bastion": return "Bastion"
		_: return ""

static func description(id: StringName) -> String:
	match id:
		# --- base (L1) abilities (copy carried over from the old per-button tooltips) ---
		&"rend": return "Adds a Slashing reel that deals no damage but applies stacking BLEED on a hit. Usable alongside your Ultimate."
		&"heft": return "Converts this turn's miss faces into hits (steadier spin). Rampage already includes Heft for free."
		&"flurry": return "Adds one extra weapon swing (reel) this turn. Usable alongside your Ultimate."
		&"reroll": return "After the spin, re-rolls your single worst reel (refunded if none were bad). Wildcard Gamble already re-rolls everything."
		&"hunters_mark": return "Marks the target for 3 turns — allies' crit-fails become hits against it. Usable alongside your Ultimate."
		&"select_fate": return "Adds a reel (joins paylines) and converts this whole spin to a damage type you pick. Locked out while The Big Bang is staged — the Ultimate picks the type for free."
		&"rallying_cry": return "Adds a no-damage reel; on a hit, shields every ally for 2 turns — half your weapon's damage on a success, full on a crit. Usable alongside Earthquake."
		# --- Warrior ---
		&"sundering_strike": return "Slashing attack reel; on a hit, SUNDERS the target — it takes ×1.25 damage for 2 turns."
		&"heroic_guard": return "Self: GUARDED (incoming damage ×0.75) and TAUNT (enemies are drawn to attack you), 2 turns."
		&"second_wind": return "Self: heal 30% of max HP, cleanse ALL debuffs, and gain GUARDED (incoming ×0.75) for 2 turns."
		# --- Vanguard ---
		&"bloodwrath": return "Self: EMPOWERED scaling with missing HP — +1% outgoing damage per 2% HP missing (cap +40%), 2 turns."
		&"quake_slam": return "Crushing attack reel; on a hit, reliably SLOWS the target (−20 initiative, stacking)."
		&"mountain_stance": return "Self: heavy GUARDED (incoming ×0.5), immunity to Slow/Stun/Root, and TAUNT, 3 turns."
		# --- Skirmisher ---
		&"feint_riposte": return "Self: EVASION (incoming hits become misses) and TAUNT — bait attacks while evasive, 2 turns. Each whiff against you builds a riposte charge."
		&"quickstep": return "Self: HASTE — +20 initiative for 2 turns (you act earlier)."
		&"riposte_storm": return "Consumes your riposte charges: a nova reel deals +15% weapon damage per charge (cap 5), then charges reset to 0. Fires at baseline with 0 charges."
		# --- Chancer ---
		&"loaded_dice": return "This spin only: adds crit faces to your reels and lights one bonus payline."
		&"jinx_the_odds": return "Attack reel; on a hit, JINXES the target for 2 turns — its successes downgrade (success→neutral, crit→success)."
		&"double_or_nothing": return "All-in gamble: next spin is EMPOWERED ×1.5. Each non-fail reel refunds 1 Stamina — but every crit-fail reel deals its own rolled damage back to YOU."
		# --- Ranger ---
		&"aimed_shot": return "Piercing reel with a one-shot EMPOWERED boost baked in; extra multiplier if the target is Hunter's-Marked."
		&"snare_trap": return "Attack reel; on a hit, ROOTS the target — −30 initiative for 2 turns."
		&"crippling_shot": return "Piercing called shot; on a hit, WEAKENS the target (its outgoing damage ×0.75, 2 turns) and deals +50% bonus damage if it's Slowed, Rooted, or Stunned."
		# --- Seer ---
		&"hex": return "Mystic attack reel; on a hit, CURSES the target — stacking damage-over-time (Bleed-style tiers), 3 turns."
		&"foresight": return "Shields your lowest-HP ally for ~15% of your max Mana (auto-targets)."
		&"mana_surge": return "Self: your next spin only is EMPOWERED ×1.6 — a one-turn damage spike."
		# --- Warden ---
		&"entangle": return "Earth attack reel; on a hit, ROOTS the target — −30 initiative for 2 turns."
		&"regrowth": return "Grants your lowest-HP ally REGEN — stacking regeneration that heals each turn (Bleed-style tiers), 3 turns (auto-targets)."
		&"bastion": return "Self: heavy GUARDED (incoming ×0.5), TAUNT, and THORNS — attackers take back 20% of the damage they deal, 3 turns."
		_: return ""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_catalog.gd`
Expected: 59 "ok" lines (28 ids × 2 checks + 3 top-level), no FAIL.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/ability_catalog.gd tests/test_ability_catalog.gd
git commit -m "feat(ui): add AbilityCatalog — one source of truth for all 28 ability names/descriptions"
```

---

## Task 2: `AbilityMenuPanel` pure statics (`row_state` / `cost_text` / `cooldown_text`)

**Files:**
- Create: `combat/ui/ability_menu_panel.gd` (statics + class skeleton only; the view is Task 3)
- Test: `tests/test_ability_menu_state.gd`

**Interfaces:**
- Consumes: `MainPhasePlan.ability_staged/staged_extra_ability_id/ability_is_free()/
  ability_locked_by_ultimate()/can_stage_ability()/can_stage_extra_ability(id)` and
  `Combatant.ability_id/is_on_cooldown(id)/cooldowns/find_extra_ability(id)` — all existing.
- Produces: `AbilityMenuPanel.RowState` enum `{NORMAL, STAGED, UNAFFORDABLE, ON_COOLDOWN,
  LOCKED_BY_ULTIMATE, INCLUDED_FREE}`;
  `AbilityMenuPanel.row_state(plan: MainPhasePlan, c: Combatant, id: StringName) -> RowState`;
  `AbilityMenuPanel.cost_text(plan: MainPhasePlan, c: Combatant, id: StringName) -> String`;
  `AbilityMenuPanel.cooldown_text(c: Combatant, id: StringName) -> String`.
  Task 3 renders rows from these; Task 3's test reuses them as oracles.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_menu_state.gd`:

```gdscript
extends SceneTree

## Pure row-state logic for the ability menu (spec 2026-07-02 §2 table) — every state, no scene tree.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_combatant() -> Combatant:
	var c: Combatant = Combatant.new()
	c.is_player = true
	c.level = 9
	c.ability_id = &"flurry"
	c.ability_resource = &"stamina"
	c.resource_pool = ResourcePool.new()
	c.resource_pool.stamina = 10
	c.resource_pool.max_stamina = 10
	var a: AbilityDef = AbilityDef.new()
	a.id = &"riposte_storm"; a.unlock_level = 9; a.cost = 4; a.resource = &"stamina"; a.cooldown_turns = 3
	c.extra_abilities = [a]
	return c

func _init() -> void:
	var c: Combatant = _make_combatant()
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2)

	# Base-ability states.
	_check(AbilityMenuPanel.row_state(plan, c, &"flurry") == AbilityMenuPanel.RowState.NORMAL, "base: NORMAL when stageable")
	plan.toggle_ability()
	_check(AbilityMenuPanel.row_state(plan, c, &"flurry") == AbilityMenuPanel.RowState.STAGED, "base: STAGED after toggle")
	plan.toggle_ability()
	c.resource_pool.stamina = 0
	_check(AbilityMenuPanel.row_state(plan, c, &"flurry") == AbilityMenuPanel.RowState.UNAFFORDABLE, "base: UNAFFORDABLE at 0 STA")
	c.resource_pool.stamina = 10

	# Extra-ability states.
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.NORMAL, "extra: NORMAL when stageable")
	plan.toggle_extra_ability(&"riposte_storm")
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.STAGED, "extra: STAGED after toggle")
	plan.toggle_extra_ability(&"riposte_storm")
	c.start_cooldown(&"riposte_storm", 3)
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.ON_COOLDOWN, "extra: ON_COOLDOWN")
	_check(AbilityMenuPanel.cooldown_text(c, &"riposte_storm") == "On cooldown: 3 turns", "cooldown text shows remaining turns")
	c.cooldowns.clear()
	_check(AbilityMenuPanel.cooldown_text(c, &"riposte_storm") == "Ready — 3-turn cooldown after use", "L9 off-cooldown text warns of CD")
	c.resource_pool.stamina = 0
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.UNAFFORDABLE, "extra: UNAFFORDABLE at 0 STA")
	c.resource_pool.stamina = 10

	# LOCKED_BY_ULTIMATE: Chancer's Wildcard Gamble subsumes Re-roll.
	var chancer: Combatant = _make_combatant()
	chancer.ability_id = &"reroll"
	chancer.ultimate_id = &"wildcard_gamble"
	var plan2: MainPhasePlan = MainPhasePlan.new(chancer, 4)
	plan2.fire_ultimate_staged = true
	_check(AbilityMenuPanel.row_state(plan2, chancer, &"reroll") == AbilityMenuPanel.RowState.LOCKED_BY_ULTIMATE, "base: LOCKED_BY_ULTIMATE under Wildcard Gamble")

	# INCLUDED_FREE: Vanguard's Rampage bakes in Heft.
	var van: Combatant = _make_combatant()
	van.ability_id = &"heft"
	van.ultimate_id = &"rampage"
	var plan3: MainPhasePlan = MainPhasePlan.new(van, 2)
	plan3.fire_ultimate_staged = true
	_check(AbilityMenuPanel.row_state(plan3, van, &"heft") == AbilityMenuPanel.RowState.INCLUDED_FREE, "base: INCLUDED_FREE under Rampage")

	# Cost text: base from the plan's rail/cost, extra from its AbilityDef, all-in special case.
	_check(AbilityMenuPanel.cost_text(plan, c, &"flurry") == "2 STA", "base cost text")
	_check(AbilityMenuPanel.cost_text(plan, c, &"riposte_storm") == "4 STA", "extra cost text")
	var don: AbilityDef = AbilityDef.new()
	don.id = &"double_or_nothing"; don.unlock_level = 9; don.cost = 0; don.resource = &"stamina"; don.cooldown_turns = 7
	c.extra_abilities.append(don)
	_check(AbilityMenuPanel.cost_text(plan, c, &"double_or_nothing") == "all-in: ALL remaining Stamina", "Double or Nothing cost text")
	var mana_c: Combatant = _make_combatant()
	mana_c.ability_id = &"rallying_cry"
	mana_c.ability_resource = &"mana"
	var plan4: MainPhasePlan = MainPhasePlan.new(mana_c, 4)
	_check(AbilityMenuPanel.cost_text(plan4, mana_c, &"rallying_cry") == "4 MANA", "mana rail cost text")
	_check(AbilityMenuPanel.cooldown_text(c, &"flurry") == "Ready", "base ability cooldown text is Ready")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_state.gd`
Expected: FAIL to load — `AbilityMenuPanel` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `combat/ui/ability_menu_panel.gd` with the statics ONLY (the view methods land in Task 3):

```gdscript
class_name AbilityMenuPanel
extends Panel

## Non-modal floating ability menu (spec 2026-07-02): one row per UNLOCKED ability (base L1 first,
## then L5/L7/L9), each a stage/un-stage toggle. Locked abilities are HIDDEN (player-locked rule).
## Opened by the combat scene's Abilities button; TypeChartPanel float-over-the-reels precedent.
## This file also owns the PURE row logic (row_state/cost_text/cooldown_text) so it's unit-testable
## headless without building a scene.

signal ability_pressed(id: StringName)

## Everything the old single base-ability button could render, as one enum (spec §2 table).
enum RowState { NORMAL, STAGED, UNAFFORDABLE, ON_COOLDOWN, LOCKED_BY_ULTIMATE, INCLUDED_FREE }

## The menu-row state for ability [param id] under the current plan. Base and extra abilities have
## different model gates (single ability_staged bool vs staged_extra_ability_id) — this is the one
## place that difference is flattened for the UI.
static func row_state(plan: MainPhasePlan, c: Combatant, id: StringName) -> RowState:
	if c != null and id == c.ability_id:
		if plan.ability_is_free():
			return RowState.INCLUDED_FREE
		if plan.ability_locked_by_ultimate():
			return RowState.LOCKED_BY_ULTIMATE
		if plan.ability_staged:
			return RowState.STAGED
		if plan.can_stage_ability():
			return RowState.NORMAL
		return RowState.UNAFFORDABLE
	if plan.staged_extra_ability_id == id:
		return RowState.STAGED
	if c != null and c.is_on_cooldown(id):
		return RowState.ON_COOLDOWN
	if plan.can_stage_extra_ability(id):
		return RowState.NORMAL
	return RowState.UNAFFORDABLE

## "2 STA" / "4 MANA", read LIVE from the plan (base) or AbilityDef (extra) — never from the catalog.
static func cost_text(plan: MainPhasePlan, c: Combatant, id: StringName) -> String:
	if id == &"double_or_nothing":
		return "all-in: ALL remaining Stamina"
	if c != null and id == c.ability_id:
		return "%d %s" % [plan.ability_cost, _rail_label(c.ability_resource)]
	var def: AbilityDef = c.find_extra_ability(id) if c != null else null
	if def == null:
		return ""
	return "%d %s" % [def.cost, _rail_label(def.resource)]

## "Ready" / "On cooldown: N turns" / "Ready — N-turn cooldown after use" (spec §2).
static func cooldown_text(c: Combatant, id: StringName) -> String:
	if c == null or id == c.ability_id:
		return "Ready"  # base abilities have no cooldowns
	if c.is_on_cooldown(id):
		return "On cooldown: %d turns" % int(c.cooldowns.get(id, 0))
	var def: AbilityDef = c.find_extra_ability(id)
	if def != null and def.cooldown_turns > 0:
		return "Ready — %d-turn cooldown after use" % def.cooldown_turns
	return "Ready"

static func _rail_label(resource: StringName) -> String:
	return "MANA" if resource == &"mana" else "STA"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_state.gd`
Expected: 16 "ok" lines, no FAIL.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/ability_menu_panel.gd tests/test_ability_menu_state.gd
git commit -m "feat(ui): AbilityMenuPanel pure row logic (state/cost/cooldown text)"
```

---

## Task 3: `AbilityMenuPanel` view (`open_for` row building)

**Files:**
- Modify: `combat/ui/ability_menu_panel.gd` (add the view methods below the Task-2 statics)
- Test: `tests/test_ability_menu_panel.gd`

**Interfaces:**
- Consumes: `AbilityCatalog.display_name/description` (Task 1); Task 2's statics;
  `Combatant.unlocked_extra_abilities() -> Array[AbilityDef]` (existing).
- Produces: `open_for(c: Combatant, plan: MainPhasePlan) -> void` (rebuild + show),
  `row_ids() -> Array[StringName]` (unlock-ordered ids of the rows built — test hook),
  signal `ability_pressed(id: StringName)`. Task 4 connects the signal and calls `open_for`/`hide`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ability_menu_panel.gd`:

```gdscript
extends SceneTree

## View-layer smoke: open_for builds one row per UNLOCKED ability in unlock order, hides locked
## ones entirely (player-locked rule), and rebuilds (never accumulates) on every open.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"warden")
	var c: Combatant = cc.build_combatant(true)
	var plan: MainPhasePlan = MainPhasePlan.new(c, c.ability_cost)
	var panel: AbilityMenuPanel = AbilityMenuPanel.new()

	c.level = 1
	panel.open_for(c, plan)
	_check(panel.row_ids() == [&"rallying_cry"] as Array[StringName], "level 1: only the base ability row")
	_check(panel.visible, "open_for shows the panel")

	c.level = 9
	panel.open_for(c, plan)
	var want: Array[StringName] = [&"rallying_cry", &"entangle", &"regrowth", &"bastion"]
	_check(panel.row_ids() == want, "level 9: 4 rows in unlock order (base, L5, L7, L9)")

	panel.open_for(c, plan)
	_check(panel.row_ids() == want, "re-open rebuilds instead of accumulating rows")

	var got: Array[StringName] = []
	panel.ability_pressed.connect(func(id: StringName) -> void: got.append(id))
	panel.press_row_for_test(&"entangle")
	_check(got == [&"entangle"] as Array[StringName], "pressing a row emits ability_pressed(id)")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_panel.gd`
Expected: FAIL — `open_for`/`row_ids`/`press_row_for_test` don't exist.

- [ ] **Step 3: Write minimal implementation**

Append to `combat/ui/ability_menu_panel.gd` (below the Task-2 statics):

```gdscript
const PAD: float = 12.0
const TITLE_H: float = 26.0
const ROW_H: float = 64.0
const BTN_W: float = 300.0
const INFO_W: float = 520.0

const COLOR_STAGED := Color(0.6, 1.0, 0.6)
const COLOR_LOCKED := Color(0.5, 0.5, 0.5)

var _row_ids: Array[StringName] = []
var _row_buttons: Dictionary = {}  # StringName -> Button

## Rebuilds the menu for [param c]'s current unlocked kit + [param plan]'s staged state, then shows
## it. Called on every open and after an in-place state change — rows are never cached (spec §2).
func open_for(c: Combatant, plan: MainPhasePlan) -> void:
	for child in get_children():
		child.queue_free()
	_row_ids.clear()
	_row_buttons.clear()
	if c == null or plan == null:
		return
	if c.ability_id != &"":
		_row_ids.append(c.ability_id)
	for def: AbilityDef in c.unlocked_extra_abilities():
		_row_ids.append(def.id)

	var title := Label.new()
	title.text = "Abilities — stage one for this turn (press it again to un-stage)"
	title.position = Vector2(PAD, PAD - 2.0)
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	var top: float = PAD + TITLE_H
	for i: int in range(_row_ids.size()):
		_build_row(_row_ids[i], c, plan, top + float(i) * ROW_H)

	custom_minimum_size = Vector2(PAD * 2.0 + BTN_W + 12.0 + INFO_W, top + float(_row_ids.size()) * ROW_H + PAD)
	size = custom_minimum_size
	show()

## One row: a toggle Button (name + live cost) and an info Label (description + cooldown/state line).
func _build_row(id: StringName, c: Combatant, plan: MainPhasePlan, y: float) -> void:
	var state: RowState = row_state(plan, c, id)

	var btn := Button.new()
	btn.text = "%s  (%s)" % [AbilityCatalog.display_name(id), cost_text(plan, c, id)]
	btn.position = Vector2(PAD, y)
	btn.custom_minimum_size = Vector2(BTN_W, ROW_H - 10.0)
	var status: String = cooldown_text(c, id)
	match state:
		RowState.STAGED:
			btn.text += "  ✓"
			btn.modulate = COLOR_STAGED
		RowState.UNAFFORDABLE:
			btn.disabled = true
		RowState.ON_COOLDOWN:
			btn.disabled = true
		RowState.LOCKED_BY_ULTIMATE:
			btn.disabled = true
			btn.modulate = COLOR_LOCKED
			status = "Locked — the staged Ultimate already includes this"
		RowState.INCLUDED_FREE:
			btn.disabled = true
			btn.modulate = COLOR_STAGED
			status = "Included by Rampage — free"
		_:
			pass
	btn.pressed.connect(func() -> void: ability_pressed.emit(id))
	add_child(btn)
	_row_buttons[id] = btn

	var info := Label.new()
	info.text = "%s\n%s" % [AbilityCatalog.description(id), status]
	info.position = Vector2(PAD + BTN_W + 12.0, y)
	info.custom_minimum_size = Vector2(INFO_W, ROW_H - 10.0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	add_child(info)

## The unlock-ordered ability ids currently rendered as rows (test hook).
func row_ids() -> Array[StringName]:
	return _row_ids.duplicate()

## Presses row [param id]'s button programmatically (headless test hook — emits like a real click).
func press_row_for_test(id: StringName) -> void:
	var btn: Button = _row_buttons.get(id, null)
	if btn != null and not btn.disabled:
		btn.pressed.emit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_panel.gd`
Expected: 5 "ok" lines, no FAIL.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/ability_menu_panel.gd tests/test_ability_menu_panel.gd
git commit -m "feat(ui): AbilityMenuPanel view — unlock-ordered rows, hidden-when-locked, ability_pressed signal"
```

---

## Task 4: `combat.gd` wiring — the Abilities button + menu dispatch

**Files:**
- Modify: `combat/combat.gd` (line anchors below are pre-change; verify each with a search first)

**Interfaces:**
- Consumes: `AbilityMenuPanel.open_for/row_ids/ability_pressed` (Task 3), `AbilityCatalog.display_name`
  (Task 1), existing `MainPhasePlan.toggle_ability()/toggle_extra_ability(id)/stage_select_fate()`.
- Produces: the live scene behavior. No new public API.

**No new headless test in this task** — the wiring is exercised by the existing scene-load smoke
suites (`test_scene_load_seer.gd`, `test_scene_party_smoke.gd`), which parse/instantiate `combat.gd`
and fail on any broken identifier; the interactive flow is the human playtest (CLAUDE.md §5 ceiling).

- [ ] **Step 1: Rename `_splice_button` → `_abilities_button` project-wide in combat.gd**

Search-replace ALL occurrences of `_splice_button` with `_abilities_button` in `combat/combat.gd`
(declaration line 37; build lines 253–258; connect line 738; turn-start lines 841–842; disable
lines 857, 881, 963, 965, 1586, 1588; preview block lines 1044–1059). `grep -n _splice_button`
afterwards must return nothing.

- [ ] **Step 2: Rebuild the button + instantiate the panel in `_build_ui`**

Replace the (renamed) button-construction block (was lines 253–258):

```gdscript
	_abilities_button = Button.new()
	_abilities_button.text = "Abilities"
	_abilities_button.position = Vector2(col_x.call(1), ROW1_Y)
	_abilities_button.custom_minimum_size = Vector2(BTN_W, 50)
	_abilities_button.disabled = true
	_abilities_button.tooltip_text = "Open your ability list — stage one ability for this turn."
	add_child(_abilities_button)
```

Add a member near `var _type_chart: TypeChartPanel` (~line 50s, with the other UI members):

```gdscript
var _ability_menu: AbilityMenuPanel
```

In `_build_ui`, right after the `_type_chart` block (~line 315, after `_type_chart.build()`):

```gdscript
	# Ability menu — floats over the reel area while open (spec 2026-07-02); rebuilt on every open.
	_ability_menu = AbilityMenuPanel.new()
	_ability_menu.position = Vector2(CENTER_X + 30.0, 96.0)
	_ability_menu.visible = false
	add_child(_ability_menu)
```

- [ ] **Step 3: Rewire the handlers**

In `_bind_signals` (line 738 area), replace the old connect with:

```gdscript
	_abilities_button.pressed.connect(_on_abilities_pressed)
	_ability_menu.ability_pressed.connect(_on_ability_menu_ability_pressed)
```

Replace the whole `_on_splice_pressed` function (was lines 999–1009) with:

```gdscript
## Opens/closes the ability menu (spec 2026-07-02 §1). All staging happens INSIDE the menu — this
## button is only the door (and, via _refresh_main1_preview, the staged-state readout).
func _on_abilities_pressed() -> void:
	if _ability_menu.visible:
		_ability_menu.hide()
		return
	if not _awaiting_player_spin or _plan == null:
		return
	_ability_menu.open_for(_attacker, _plan)
	move_child(_ability_menu, get_child_count() - 1)  # draw over the reel strips while up

## One menu row pressed: dispatch to the existing model (base slot vs extra slot — mutual exclusivity
## is model-enforced, never policed here). A SUCCESSFUL stage/un-stage closes the menu so the reel/
## resource preview is immediately visible; a no-op press re-renders the menu in place (spec §3).
func _on_ability_menu_ability_pressed(id: StringName) -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	var before: String = _staged_state_key()
	if id == _attacker.ability_id:
		if _attacker.ability_id == &"select_fate" and not _plan.ability_staged:
			_ability_menu.hide()  # the type picker is modal — close the menu under it
			_show_fate_picker()
			return
		_plan.toggle_ability()
	else:
		_plan.toggle_extra_ability(id)
	if _staged_state_key() != before:
		_ability_menu.hide()
	else:
		_ability_menu.open_for(_attacker, _plan)  # re-render states in place (e.g. press was a no-op)
	_refresh_main1_preview()

## Fingerprint of the plan's staged-ability state — compared around a toggle to detect "something
## actually changed" (drives the close-on-successful-toggle rule).
func _staged_state_key() -> String:
	return "%s|%s" % [str(_plan.ability_staged), String(_plan.staged_extra_ability_id)]
```

- [ ] **Step 4: Rewrite the preview block + add close conditions**

In `_refresh_main1_preview` (was lines 1040–1059), replace the whole base-ability-button block
(everything from the `if _plan.ability_is_free():` line through the `_splice_button.modulate = ...`
line inside the `else:`) with:

```gdscript
	# Abilities button (spec 2026-07-02 §1): the staged choice must be legible with the menu CLOSED —
	# show the staged ability's name + staged-green on the button itself.
	var staged_name: String = ""
	if _plan.staged_extra_ability_id != &"":
		staged_name = AbilityCatalog.display_name(_plan.staged_extra_ability_id)
	elif _plan.ability_staged or _plan.ability_is_free():
		if _attacker.ability_id == &"select_fate" and _plan.selected_fate_type != null:
			staged_name = "Select Fate: %s" % _type_name(_plan.selected_fate_type)
		else:
			staged_name = AbilityCatalog.display_name(_attacker.ability_id)
	if staged_name != "":
		_abilities_button.text = "Abilities: %s ✓" % staged_name
		_abilities_button.modulate = Color(0.6, 1.0, 0.6)
	else:
		_abilities_button.text = "Abilities"
		_abilities_button.modulate = Color(1, 1, 1)
	# The menu is openable whenever it's the player's own Main 1 — even if nothing is currently
	# stageable, the player can still READ their kit (legibility pillar).
	_abilities_button.disabled = not is_player_main1
	if _ability_menu.visible:
		_ability_menu.open_for(_attacker, _plan)  # keep an open menu's row states live
```

In `_on_turn_started` (was lines 841–842): the two renamed lines
`_abilities_button.text = _ability_label(ctrl.ability_id)` and
`_abilities_button.tooltip_text = _ability_tooltip(ctrl.ability_id)` are now wrong — DELETE both
(the button's text is owned by `_refresh_main1_preview`; the tooltip is static from `_build_ui`).
Add a close at the top of the function body (right after `_attacker = c`):

```gdscript
	_ability_menu.hide()  # never carry an open menu across a turn boundary
```

In `_on_spin_pressed` (was line ~962, next to the other button disables), add:

```gdscript
	_ability_menu.hide()
```

- [ ] **Step 5: Migrate the copy helpers to the catalog**

DELETE the now-dead `_ability_label` (was lines 774–783) and `_ability_tooltip` (was lines 610–619)
functions entirely. Re-point `_ability_name` (was lines 786–795, used by the combat log) at the
catalog:

```gdscript
## Short ability name for the combat log — catalog-backed (one source of truth, spec 2026-07-02 §4).
func _ability_name(id: StringName) -> String:
	var display: String = AbilityCatalog.display_name(id)  # not "name" — would shadow Node.name
	return display if display != "" else "ability"
```

Then `grep -n "_ability_label\|_ability_tooltip" combat/combat.gd` — must return nothing. If any
OTHER caller of either function turns up (e.g. a selection-screen tooltip builder), re-point it at
`AbilityCatalog.display_name`/`description` instead of deleting it blind.

- [ ] **Step 6: Verify — scene smoke + targeted suites**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_scene_load_seer.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_scene_party_smoke.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_menu_panel.gd
```
Expected: all "ok", no FAIL, no script-parse errors in the output.

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(ui): Abilities button + menu wiring — stage any unlocked ability from one panel"
```

---

## Task 5: Full regression + status docs

**Files:**
- Modify: `CLAUDE.md` (§8 status)

- [ ] **Step 1: Full regression**

Run the Global Constraints PowerShell loop over all `tests/test_*.gd`.
Expected: `ALL GREEN` (106 suites: 103 prior + 3 new).

- [ ] **Step 2: Update CLAUDE.md §8**

Replace the `> **⚠ NOT PLAYTEST-READY — NO UI EXISTS FOR THE 21 NEW ABILITIES.** …` blockquote
(keeping the Regrowth-fix paragraph that follows it) with:

```markdown
> **Ability-menu UI SHIPPED (2026-07-02, spec `2026-07-02-ability-menu-ui-design.md`):** the old
> single base-ability button is now an **"Abilities" button** opening a floating `AbilityMenuPanel`
> (TypeChartPanel precedent): one toggle row per UNLOCKED ability (locked ones hidden — player rule),
> with live cost/cooldown text and `AbilityCatalog` descriptions (one source of truth for all 28
> ability names/descriptions; costs/CDs read live from AbilityDef, never duplicated). Staging closes
> the menu so the preview shows; the button reads "Abilities: <name> ✓" while staged. Ultimate button
> unchanged. All 21 new abilities are now clickable in the live scene — the ENDGAME-kit human
> playtest is UNBLOCKED.
```

And rewrite the `**Next:**` paragraph to point at the playtest instead of the UI build:

```markdown
**Next:** human playtest of the full ENDGAME kit (now unblocked): spawn level-9 PCs, fire every new
ability and Ultimate at least once via the Abilities menu, and confirm the four orchestrator-level
abilities (Double or Nothing, Aimed Shot, Foresight/Regrowth, Crippling Shot) do what their tests
assert in a live fight; only after that, tune the `[ASSUMPTION]` numbers. This sits alongside (not
blocking) the still-open party-fight/enemy-AI playtest and the Seer/Ranger Ultimate playtests below.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: ability-menu UI shipped — ENDGAME-kit playtest unblocked"
```

---

## Self-Review Notes

- **Spec coverage:** §1 button → Task 4 steps 2/4; §2 panel/rows/states → Tasks 2–3; §3 interaction
  (dispatch, fate picker, close conditions, untouched commit path) → Task 4 step 3/4 (commit path:
  no task touches it — by design); §4 catalog + both tests → Tasks 1–2; out-of-scope respected (no
  model files in any task's file list).
- **Type consistency:** `row_state(plan, c, id)`, `cost_text(plan, c, id)`, `cooldown_text(c, id)`,
  `open_for(c, plan)`, `row_ids()`, signal `ability_pressed(id: StringName)` — used identically in
  Tasks 2, 3, and 4.
- **Line anchors** in Task 4 are pre-change positions from the 2026-07-02 working tree; each step
  says to locate by search, not blind offset.
