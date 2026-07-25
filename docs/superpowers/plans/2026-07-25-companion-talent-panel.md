# Companion Talent Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player view/edit the Ability Talent + Universal Perk picks of the PC's active companions (not just the PC) through `TalentMenuPanel`, via a per-character switcher, with picks surviving a bench → re-add cycle using the project's existing object-reference persistence (no new save system).

**Architecture:** `TalentMenuPanel` grows from a single-`Combatant` view into a `_party: Array[Combatant]` (PC + up to 2 active companions) + `_viewed_index`, with a row of switcher tab buttons driving which member's grid is shown. A fresh `open_for()` call always defaults to viewing the PC; switching tabs while open is a separate, narrower rebuild path (`_rebuild()`) that does not reset which member is viewed. The three world scenes (town/overworld/dungeon) pass their existing `_companions` array into `open_for()`. No persistence code is added — companions are already held by `Resource` reference across bench/re-add and scene transitions, so `ability_talent_picks`/`talent_perks` (already fields on `Combatant`) persist automatically, proven by an end-to-end test.

**Tech Stack:** Godot 4.6 / GDScript, headless test suite (`Godot_v4.6.3-stable_win64_console.exe --headless --path <repo> --script res://tests/test_<name>.gd`).

## Global Constraints

- GDScript only, static typing throughout (typed vars/params/returns) — CLAUDE.md §2.
- `PascalCase` classes, `snake_case` script files/methods — CLAUDE.md §2.
- No placeholder/TBD code; every step below is complete, runnable GDScript.
- The Godot executable lives ONE DIRECTORY ABOVE this repo:
  `C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe` (repo root is
  `C:/bunnies/bunnies-main/bunnies`). Run tests with:
  `"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_<name>.gd`
  Exit code `0` = pass. Harmless `RID allocations leaked` / `ObjectDB instances leaked` warnings at
  process exit are pre-existing noise in this project's headless runs, not failures — judge pass/
  fail by exit code, not by the presence of those specific warning lines.
- Never delete `.godot/` to troubleshoot a test failure (gitignored, but wipes the project-wide
  class_name registry).
- Stage and commit only the files each task actually touches — this repo currently has many
  unrelated pre-existing untracked files sitting in the working tree; do not sweep them into a
  commit with a broad `git add`.

---

### Task 1: `TalentMenuPanel` party switcher

**Files:**
- Modify: `combat/ui/talent_menu_panel.gd`
- Test: `tests/test_talent_menu_panel.gd`

**Interfaces:**
- Consumes: `Combatant.display_name`, `Combatant.ability_talent_picks`, `Combatant.talent_perks`,
  `Combatant.has_ability_talent()`, `Combatant.pick_ability_talent()`,
  `Combatant.ability_talent_row_unlocked()` (all pre-existing, unchanged).
- Produces: `TalentMenuPanel.open_for(pc: Combatant, companions: Array, respec_available: bool = true)`
  (signature CHANGE — was `open_for(c: Combatant, respec_available: bool = true)`; every caller in
  the codebase must be updated, see Task 2), `party_tab_count() -> int`,
  `press_party_tab_for_test(index: int) -> bool`, `viewed_combatant_for_test() -> Combatant`. All
  pre-existing test hooks (`row_button_count`, `is_row_interactive`, `press_option_for_test`, etc.)
  keep their exact same names/signatures/behavior.

- [ ] **Step 1: Update the existing test file's calls to the new signature and add switcher assertions**

Replace the entire contents of `tests/test_talent_menu_panel.gd` with:

```gdscript
extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_warrior_at(level: int) -> Combatant:
	var c: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c.level = level
	return c

func _init() -> void:
	var panel: TalentMenuPanel = TalentMenuPanel.new()

	# All 6 Ability Talent rows render for the viewed character's class, even locked ones.
	var c: Combatant = _mk_warrior_at(5)  # only base_ability row unlocked
	panel.open_for(c, [], true)
	_check(panel.row_button_count(&"base_ability") == 3, "base_ability row (unlocked at L5) shows 3 option buttons")
	_check(panel.row_button_count(&"ultimate") == 3, "ultimate row (locked until L10) STILL shows 3 option buttons — locked rows are shown, not hidden")
	_check(not panel.is_row_interactive(&"ultimate"), "a locked row's buttons are disabled")
	_check(panel.is_row_interactive(&"base_ability"), "an unlocked row's buttons are enabled")
	_check(panel.locked_row_label(&"ultimate") == "Unlocks at Level 10", "a locked row shows its unlock level (got '%s')" % panel.locked_row_label(&"ultimate"))
	panel.close()

	# Picking via the panel calls through to the real Combatant methods (no separate pick state).
	var c2: Combatant = _mk_warrior_at(10)
	panel.open_for(c2, [], true)
	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "pressing an option button picks it")
	_check(c2.has_ability_talent(&"rend_efficient"), "the real Combatant now has the talent picked")
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "the panel shows the picked option as selected")
	panel.close()

	# Respec gating: town (respec_available=true) allows swapping an already-spent row; overworld/
	# dungeon (false) shows the pick but disables the swap action — mirrors InventoryMenuPanel's
	# existing vault_available convention exactly.
	var c3: Combatant = _mk_warrior_at(10)
	c3.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c3, [], false)
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "an already-spent pick is still shown outside a safe zone")
	_check(not panel.is_row_interactive(&"base_ability"), "an already-spent row's buttons are disabled outside a safe zone (view-only)")
	panel.close()

	panel.open_for(c3, [], true)
	_check(panel.is_row_interactive(&"base_ability"), "the same already-spent row IS interactive in town (respec_available=true)")
	_check(panel.press_option_for_test(&"base_ability", &"rend_deeper_cut"), "town respec: picking a different option in an already-spent row succeeds (unpick + repick)")
	_check(c3.has_ability_talent(&"rend_deeper_cut"), "the swap actually changed the Combatant's pick")
	_check(not c3.has_ability_talent(&"rend_efficient"), "the old pick is cleared")
	panel.close()

	# Universal Perk section: 5 milestone slots, shown-when-reached (unlike the Ability Talent grid's
	# always-shown rows), one-time-pick enforcement carried straight through to TalentPerkLibrary.
	var c4: Combatant = _mk_warrior_at(3)
	panel.open_for(c4, [], true)
	_check(panel.universal_slot_count() == 1, "L3: only the L2 milestone has been reached (1 slot shown, got %d)" % panel.universal_slot_count())
	panel.close()

	var c5: Combatant = _mk_warrior_at(10)
	panel.open_for(c5, [], true)
	_check(panel.universal_slot_count() == 5, "L10: all 5 milestones reached (got %d)" % panel.universal_slot_count())
	_check(panel.press_universal_perk_for_test(&"vigor_boost"), "picking a universal perk succeeds")
	_check(c5.has_ability_talent(&"") == false, "sanity: has_ability_talent is unrelated to talent_perks")
	_check(&"vigor_boost" in c5.talent_perks, "the real Combatant now carries the picked universal perk")
	panel.close()

	# Playtest-found bug (2026-07-24): pressing an EMPTY universal-perk slot's button did nothing —
	# no handler existed for that case at all. Drive the REAL button press (not the
	# press_universal_perk_for_test() bypass, which calls pick_talent_perk() directly and would
	# never have caught this) through to a real picker option press.
	var c6: Combatant = _mk_warrior_at(10)
	panel.open_for(c6, [], true)
	_check(not panel.perk_picker_open_for_test(), "sanity: the perk picker starts closed")
	_check(panel.press_universal_slot_for_test(0), "pressing an empty universal-perk slot succeeds")
	_check(panel.perk_picker_open_for_test(), "pressing an empty slot opens the perk picker")
	_check(panel.perk_picker_option_count_for_test() == 10, "the picker offers all 10 perks when none are picked yet (got %d)" % panel.perk_picker_option_count_for_test())
	_check(panel.press_perk_picker_option_for_test(&"vigor_boost"), "pressing a picker option succeeds")
	_check(&"vigor_boost" in c6.talent_perks, "the real Combatant now carries the perk chosen through the actual picker UI")
	_check(not panel.perk_picker_open_for_test(), "the picker closes after a pick (panel rebuilds)")
	panel.close()

	# Playtest-found bug (2026-07-24): Button.toggle_mode auto-flips the CLICKED button's own
	# visual state on every click. Re-pressing an already-selected option must NOT change the real
	# pick, and the rebuild must restore that button's toggle-ON state (not leave it looking
	# deselected while the pick silently survives underneath, which read as "my de-select didn't
	# stick" and then "reverted" the next time anything else rebuilt the panel).
	var c7: Combatant = _mk_warrior_at(10)
	c7.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c7, [], true)
	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "re-pressing the already-selected option is accepted (no-op on data, rebuilds the view)")
	_check(c7.has_ability_talent(&"rend_efficient"), "the pick is UNCHANGED by re-pressing its own button")
	_check(panel.is_option_selected(&"base_ability", &"rend_efficient"), "the button still shows as selected after the rebuild (not left looking deselected)")
	panel.close()

	# Same guard outside a safe zone: re-pressing an already-spent row's own option (or attempting
	# a different one) while respec is unavailable must also rebuild, not leave a stale/mismatched
	# toggle state on the buttons.
	var c8: Combatant = _mk_warrior_at(10)
	c8.pick_ability_talent(&"base_ability", &"rend_efficient")
	panel.open_for(c8, [], false)
	_check(not panel.press_option_for_test(&"base_ability", &"rend_deeper_cut"), "outside a safe zone, pressing a DIFFERENT option in an already-spent row is refused (button is disabled)")
	_check(c8.has_ability_talent(&"rend_efficient"), "the original pick survives untouched")
	panel.close()

	# Companion switcher (2026-07-25 companion-talent-panel spec): open_for() takes PC + companions,
	# defaults to viewing the PC (index 0), and switching tabs shows/edits a DIFFERENT Combatant's
	# own picks without touching anyone else's.
	var pc9: Combatant = _mk_warrior_at(10)
	var companion9: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	companion9.level = 10
	panel.open_for(pc9, [companion9], true)
	_check(panel.party_tab_count() == 2, "2 tabs shown: PC + 1 companion (got %d)" % panel.party_tab_count())
	_check(panel.viewed_combatant_for_test() == pc9, "open_for() defaults to viewing the PC (index 0)")

	_check(panel.press_option_for_test(&"base_ability", &"rend_efficient"), "picking while viewing the PC picks it on the PC")
	_check(pc9.has_ability_talent(&"rend_efficient"), "the PC's own pick landed on the PC")
	_check(not companion9.has_ability_talent(&"rend_efficient"), "the companion is untouched by a pick made while viewing the PC")

	_check(panel.press_party_tab_for_test(1), "switching to the companion's tab succeeds")
	_check(panel.viewed_combatant_for_test() == companion9, "the panel now views the companion")
	_check(not panel.is_option_selected(&"base_ability", &"rend_efficient"), "the companion's OWN base_ability row shows no pick yet (Skirmisher options differ from Warrior's)")
	_check(panel.press_option_for_test(&"base_ability", &"flurry_efficient"), "picking a Skirmisher option while viewing the companion succeeds")
	_check(companion9.has_ability_talent(&"flurry_efficient"), "the pick landed on the COMPANION")
	_check(not pc9.has_ability_talent(&"flurry_efficient"), "the PC is untouched by a pick made while viewing the companion")

	_check(panel.press_party_tab_for_test(0), "switching back to the PC's tab succeeds")
	_check(panel.viewed_combatant_for_test() == pc9, "the panel now views the PC again")
	_check(pc9.has_ability_talent(&"rend_efficient"), "the PC's earlier pick is still there after switching away and back")
	panel.close()

	var pc10: Combatant = _mk_warrior_at(10)
	panel.open_for(pc10, [], true)
	_check(panel.party_tab_count() == 1, "with no companions, exactly 1 tab (the PC) is shown")
	panel.close()

	print(("TALENT MENU PANEL TEST PASSED" if _failures == 0 else "TALENT MENU PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_talent_menu_panel.gd
```
Expected: a parse/argument-count error (`open_for()` still only takes 2 args) or, if it happens to
run, failures on `panel.party_tab_count()`/`press_party_tab_for_test()`/`viewed_combatant_for_test()`
(methods don't exist yet). Either way, a non-zero exit code.

- [ ] **Step 3: Implement the panel changes in `combat/ui/talent_menu_panel.gd`**

Edit the constants block (originally lines 22-28):

```gdscript
const PANEL_W: float = 620.0
const PANEL_H: float = 600.0
const PAD: float = 12.0
const ROW_H: float = 56.0
const OPTION_BTN_W: float = 190.0
const OPTION_BTN_H: float = 22.0
const UNIVERSAL_ROW_H: float = 24.0
const TAB_ROW_H: float = 28.0
const TAB_BTN_W: float = 150.0
```

Edit the fields block (originally lines 30-36) — append 3 new fields after `_perk_picker_container`:

```gdscript
var _combatant: Combatant
var _respec_available: bool = true
var _row_option_buttons: Dictionary = {}   # row_id -> Array[Button] (index-aligned with that row's options)
var _row_locked_labels: Dictionary = {}    # row_id -> Label
var _universal_buttons: Array[Button] = [] # index-aligned with the earned-milestone slots shown
var _universal_perk_ids_shown: Array[StringName] = []
var _perk_picker_container: Panel
var _party: Array[Combatant] = []          # PC (index 0) + up to 2 active companions
var _viewed_index: int = 0                 # which _party member the grid/perks below are showing
var _party_tab_buttons: Array[Button] = [] # index-aligned with _party
```

Edit `_clear()` to also reset the new tab-button tracking array:

```gdscript
func _clear() -> void:
	for child: Node in get_children():
		child.queue_free()
	_row_option_buttons.clear()
	_row_locked_labels.clear()
	_universal_buttons.clear()
	_universal_perk_ids_shown.clear()
	_perk_picker_container = null
	_party_tab_buttons.clear()
```

Replace `open_for()` and `close()` (originally lines 51-82) with:

```gdscript
## Opens the panel for [param pc] + [param companions] (0-2 entries, the active party — mirrors
## InventoryMenuPanel's own (pc, companions, ...) convention) — shows the CURRENTLY VIEWED member's
## own class's 6-row Ability Talent grid plus the shared Universal Perk milestone list, with a
## switcher tab per party member. Always defaults to viewing the PC (index 0) on a fresh open — no
## cross-open "remember last viewed character" state (switching tabs WHILE open is handled by
## _on_party_tab_pressed()/_rebuild(), which do NOT reset _viewed_index). [param respec_available]
## mirrors InventoryMenuPanel's vault_available convention exactly: false shows every already-spent
## pick (still presented, per this project's "still an option, just restricted" rule) but disables
## the swap/pick action on any row/slot that already has a pick, or any not-yet-reached-but-unlocked
## row a player could newly spend a point on outside a safe zone. Applies uniformly to whichever
## party member is currently viewed — it's a location gate, not a per-character one.
func open_for(pc: Combatant, companions: Array, respec_available: bool = true) -> void:
	_party = [pc]
	for c: Combatant in companions:
		_party.append(c)
	_viewed_index = 0
	_respec_available = respec_available
	_rebuild()

func close() -> void:
	hide()

## Rebuilds the whole panel for _party[_viewed_index] — shared by open_for() (fresh open, always
## PC) and every in-place update (tab switch, a pick, a respec) that must NOT reset _viewed_index.
func _rebuild() -> void:
	_clear()
	_combatant = _party[_viewed_index]
	show()

	var title: Label = Label.new()
	title.text = "Talents"
	title.position = Vector2(PAD, PAD)
	add_child(title)

	_build_party_tabs()

	var y: float = PAD + 36.0 + TAB_ROW_H
	for row_id: StringName in ROW_IDS:
		_build_row(row_id, y)
		y += ROW_H

	y += 8.0
	var universal_title: Label = Label.new()
	universal_title.text = "Universal Perks"
	universal_title.position = Vector2(PAD, y)
	add_child(universal_title)
	y += 22.0
	_build_universal_section(y)

## One switcher button per active party member, directly under the title. Clicking a DIFFERENT
## member's tab changes which character's talents are shown/edited without resetting back to the
## PC — a tab switch is a view change within the same open, unlike open_for() itself.
func _build_party_tabs() -> void:
	for i: int in range(_party.size()):
		var member: Combatant = _party[i]
		var btn: Button = Button.new()
		btn.text = member.display_name
		btn.position = Vector2(PAD + float(i) * (TAB_BTN_W + 8.0), PAD + 24.0)
		btn.size = Vector2(TAB_BTN_W, TAB_ROW_H - 4.0)
		btn.toggle_mode = true
		btn.button_pressed = (i == _viewed_index)
		btn.pressed.connect(_on_party_tab_pressed.bind(i))
		add_child(btn)
		_party_tab_buttons.append(btn)

func _on_party_tab_pressed(index: int) -> void:
	_viewed_index = index
	_rebuild()
```

Then, in the SAME file, replace every occurrence (there are exactly 6: two in `_on_option_pressed`'s
early-return branches, one at the end of `_on_option_pressed`, one in `_on_universal_slot_pressed`,
one in `_on_perk_picker_option_pressed`, one in `press_universal_perk_for_test`) of the literal call

```gdscript
open_for(_combatant, _respec_available)
```

with:

```gdscript
_rebuild()
```

These were the panel's own internal "re-render after a state change" calls — they must go through
`_rebuild()` now, not `open_for()`, or every in-panel pick/swap/perk-pick would silently snap the
view back to the PC.

Finally, append 3 new test hooks at the end of the file, after the existing
`press_universal_perk_for_test()`:

```gdscript
## Number of party-switcher tabs currently shown (headless test hook).
func party_tab_count() -> int:
	return _party_tab_buttons.size()

## Presses the real switcher tab for _party[index] (headless test hook — drives the actual
## _on_party_tab_pressed() path). Returns false if index is out of range.
func press_party_tab_for_test(index: int) -> bool:
	if index < 0 or index >= _party_tab_buttons.size():
		return false
	_on_party_tab_pressed(index)
	return true

## The Combatant currently being viewed/edited (headless test hook).
func viewed_combatant_for_test() -> Combatant:
	return _combatant
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_talent_menu_panel.gd
```
Expected: exit code `0`, `TALENT MENU PANEL TEST PASSED` printed, no `FAIL:` lines.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/talent_menu_panel.gd tests/test_talent_menu_panel.gd
git commit -m "feat(talents): add PC/companion switcher to TalentMenuPanel"
```

---

### Task 2: Wire the active party into every scene's talent toggle

**Files:**
- Modify: `world/town_demo.gd:625`
- Modify: `world/overworld_demo.gd:585`
- Modify: `world/dungeon_demo.gd:511`
- Test: `tests/test_town_demo_talents.gd`
- Test: `tests/test_overworld_demo_talents.gd`
- Test: `tests/test_dungeon_demo_talents.gd`

**Interfaces:**
- Consumes: `TalentMenuPanel.open_for(pc, companions, respec_available)` (Task 1),
  `TalentMenuPanel.party_tab_count()`/`press_party_tab_for_test()`/`viewed_combatant_for_test()`
  (Task 1), each scene's pre-existing `_companions: Array`/`Array[Combatant]` field.
- Produces: nothing new consumed by later tasks.

- [ ] **Step 1: Add switcher assertions to the 3 wiring smoke tests (RED first)**

In `tests/test_town_demo_talents.gd`, insert immediately after the existing line
`_check(town._pc.movement_paused_for_test(), "toggle pauses PC movement")` (inside the
`_frames == 1` block, right after the panel is first opened):

```gdscript
		_check(town._talent_panel.party_tab_count() == town._companions.size() + 1, "talent panel shows one tab per active party member (PC + companions, got %d)" % town._talent_panel.party_tab_count())
		_check(town._talent_panel.viewed_combatant_for_test() == town._pc_combatant, "the talent panel defaults to viewing the PC")
		if town._companions.size() > 0:
			_check(town._talent_panel.press_party_tab_for_test(1), "switching to the first companion's tab succeeds")
			_check(town._talent_panel.viewed_combatant_for_test() == town._companions[0], "the panel now views the real companion instance, not a copy")
```

In `tests/test_overworld_demo_talents.gd`, insert the same 5 lines (with `overworld` in place of
`town`) immediately after the existing line
`_check(overworld._pc.movement_paused_for_test(), "toggle pauses PC movement")`.

In `tests/test_dungeon_demo_talents.gd`, insert the same 5 lines (with `dungeon` in place of `town`)
immediately after the existing line
`_check(dungeon._pc.movement_paused_for_test(), "toggle pauses PC movement")`.

- [ ] **Step 2: Run all 3 tests to verify they fail**

Run each of:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_talents.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_overworld_demo_talents.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_dungeon_demo_talents.gd
```
Expected: a parse/argument-count error, since each scene's `_talent_panel.open_for(_pc_combatant, <bool>)`
call still only passes 2 arguments against Task 1's new 3-arg signature — non-zero exit code on all 3.

- [ ] **Step 3: Update the 3 call sites**

In `world/town_demo.gd`, change (in `_toggle_talents()`):
```gdscript
		_talent_panel.open_for(_pc_combatant, true)   # town = safe zone, respec available
```
to:
```gdscript
		_talent_panel.open_for(_pc_combatant, _companions, true)   # town = safe zone, respec available
```

In `world/overworld_demo.gd`, change (in `_toggle_talents()`):
```gdscript
		_talent_panel.open_for(_pc_combatant, false)   # overworld = not a safe zone, respec unavailable
```
to:
```gdscript
		_talent_panel.open_for(_pc_combatant, _companions, false)   # overworld = not a safe zone, respec unavailable
```

In `world/dungeon_demo.gd`, change (in `_toggle_talents()`):
```gdscript
		_talent_panel.open_for(_pc_combatant, false)   # dungeon = not a safe zone, respec unavailable
```
to:
```gdscript
		_talent_panel.open_for(_pc_combatant, _companions, false)   # dungeon = not a safe zone, respec unavailable
```

- [ ] **Step 4: Run all 3 tests to verify they pass**

Run the same 3 commands as Step 2. Expected: exit code `0` for all 3, each printing its own
"...wiring smoke test complete" line, no `FAIL` lines.

- [ ] **Step 5: Run the full existing test suite for regressions**

Since `TalentMenuPanel.open_for()`'s signature changed, confirm no other file calls the old 2-arg
form. Search first:
```
grep -rn "talent_panel.open_for\|TalentMenuPanel.new().open_for" --include=*.gd .
```
Expected: only the 3 call sites touched above, plus `tests/test_talent_menu_panel.gd` (already
updated in Task 1). If any other call site turns up, update it the same way (insert its own
companions array/`[]` as the second argument) before proceeding.

- [ ] **Step 6: Commit**

```bash
git add world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_town_demo_talents.gd tests/test_overworld_demo_talents.gd tests/test_dungeon_demo_talents.gd
git commit -m "feat(talents): wire the active party's companions into every scene's talent panel"
```

---

### Task 3: End-to-end proof that a companion's talent picks survive being benched

**Files:**
- Create: `tests/test_companion_talent_survives_bench.gd`

**Interfaces:**
- Consumes: `TownDemo._companions`/`_bench` (pre-existing), `TownDemo._on_add_companion_requested()`/
  `_on_remove_companion_requested()` (pre-existing, the real Party Selection production methods),
  `TownDemo._toggle_talents()` (pre-existing), `TalentMenuPanel.press_party_tab_for_test()`/
  `viewed_combatant_for_test()`/`press_option_for_test()`/`press_universal_perk_for_test()`/
  `is_option_selected()` (Task 1).
- Produces: nothing consumed by later tasks (this is the plan's final task).

- [ ] **Step 1: Write the end-to-end regression test**

Create `tests/test_companion_talent_survives_bench.gd`:

```gdscript
extends SceneTree

## End-to-end regression for the 2026-07-25 companion-talent-panel spec's central claim: benching a
## companion and re-adding them preserves their Ability Talent + Universal Perk picks, with NO new
## persistence system needed — _companions/_bench already hold the same Combatant Resource by
## reference (mirrors tests/test_bench_survives_combat.gd's real-methods, not-mocks technique,
## applied here to talent picks specifically instead of gear/HP).

var _instance: Node
var _frames: int = 0
var _companion: Combatant

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
		_check(town._companions.size() == 1, "sanity: town seeds exactly 1 active companion")
		_companion = town._companions[0]
		_companion.level = 10   # unlock every row so a pick is possible (default seed level is 3)

		town._toggle_talents()
		_check(town._talent_panel.press_party_tab_for_test(1), "switching to the companion's tab succeeds")
		_check(town._talent_panel.viewed_combatant_for_test() == _companion, "the panel is now viewing the real companion instance")
		_check(town._talent_panel.press_option_for_test(&"base_ability", &"flurry_efficient"), "picking a talent for the companion succeeds")
		_check(town._talent_panel.press_universal_perk_for_test(&"vigor_boost"), "picking a universal perk for the companion succeeds")
		_check(_companion.has_ability_talent(&"flurry_efficient"), "the real companion Combatant now carries the Ability Talent pick")
		_check(&"vigor_boost" in _companion.talent_perks, "the real companion Combatant now carries the Universal Perk pick")
		town._toggle_talents()

		# Bench the companion, then re-add — the exact real production methods Party Selection uses.
		town._on_remove_companion_requested(_companion)
		_check(_companion in town._bench, "the companion is now on the bench")
		_check(not (_companion in town._companions), "the companion is no longer in the active party")
		_check(_companion.has_ability_talent(&"flurry_efficient"), "the Ability Talent pick survives being benched")
		_check(&"vigor_boost" in _companion.talent_perks, "the Universal Perk pick survives being benched")

		town._on_add_companion_requested(_companion)
		_check(_companion in town._companions, "the companion is back in the active party")

		# Re-open the real panel and confirm it reads the SAME surviving picks, proving the whole
		# view -> data -> bench -> re-add -> view round trip, not just the raw Combatant fields.
		town._toggle_talents()
		_check(town._talent_panel.press_party_tab_for_test(1), "switching to the re-added companion's tab succeeds")
		_check(town._talent_panel.is_option_selected(&"base_ability", &"flurry_efficient"), "the panel shows the Ability Talent pick as still selected after bench + re-add")
		town._toggle_talents()

	if _frames >= 3:
		print("ok companion-talent-survives-bench regression complete")
		_instance.free()
		return true
	return false
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_companion_talent_survives_bench.gd
```
Expected: FAIL — the file is new, so this confirms it actually runs and exercises real assertions
(not a false-positive empty pass) before you've verified anything. If Tasks 1-2 are already
complete and correct, this test may in fact pass immediately since it exercises already-shipped
production code paths (bench/re-add) plus Task 1/2's new panel API — in that case, temporarily
comment out the `town._on_add_companion_requested(_companion)` line and confirm the FINAL
`is_option_selected` check then fails (proving the test can actually detect a real break), then
restore the line.

- [ ] **Step 3: Confirm it passes for real**

Run the same command as Step 2 (with the temporary break from Step 2 reverted, if you made one).
Expected: exit code `0`, `ok companion-talent-survives-bench regression complete` printed, no
`FAIL` lines.

- [ ] **Step 4: Run the full test suite once more for regressions**

Run every test file matching `tests/test_*talent*.gd` and the 3 wiring tests from Task 2 one more
time together, to confirm nothing in this task's changes disturbed them:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_talent_menu_panel.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_talents.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_overworld_demo_talents.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_dungeon_demo_talents.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_companion_talent_survives_bench.gd
```
Expected: exit code `0` on all 5.

- [ ] **Step 5: Commit**

```bash
git add tests/test_companion_talent_survives_bench.gd
git commit -m "test(talents): prove companion talent picks survive bench + re-add"
```

---

## Plan Self-Review Notes

- **Spec coverage:** Architecture change (Task 1), UI change/switcher tabs (Task 1), callers (Task
  2), testing incl. the true end-to-end bench regression (Task 3) — all 4 spec sections covered.
- **Type consistency:** `open_for(pc: Combatant, companions: Array, respec_available: bool = true)`
  is the same signature used consistently across Task 1's implementation, Task 1's test file, and
  Task 2's 3 call sites. `party_tab_count()`, `press_party_tab_for_test()`,
  `viewed_combatant_for_test()` are defined once in Task 1 and consumed with matching names/types in
  Tasks 2-3.
- **Out of scope, confirmed unchanged:** bench-roster talent editing, Ability Talent/Universal Perk
  data, unlock rules, and respec safe-zone gating logic — no task touches any of these.
