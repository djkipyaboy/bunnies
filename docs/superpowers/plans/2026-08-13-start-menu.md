# Start Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `StartMenu` boot scene (New Game / disabled Continue / Quit), wire "New Game"
through the existing `CharacterCreationScreen` into a real `town_demo.tscn` party seeded around the
created PC, and make `start_menu.tscn` the project's `main_scene` (reversing the 2026-08-10
`town_demo.tscn`-is-`main_scene` lock).

**Architecture:** `StartMenu` (a `Control`-rooted scene, built entirely in code per this project's
existing screen/panel convention) shows 3 buttons. "New Game" instances `CharacterCreationScreen`
(already built, self-contained, untouched by this plan) as a full-screen child and connects to its
`character_created(pc)` signal. On that signal, `StartMenu` calls a generalized
`InventoryDemoSetup.seed_demo_party(pc_override)` to build the rest of the demo party around the
real PC, populates the `CombatHandoff` autoload, and calls `change_scene_to_file("town_demo.tscn")`
— which already has a working `handoff.pc != null` fallback path, so it needs no changes.

**Tech Stack:** Godot 4.6 / GDScript, headless test suite
(`Godot_v4.6.3-stable_win64_console.exe --headless --path <repo> --script res://tests/test_<name>.gd`).

**Spec:** `docs/superpowers/specs/2026-08-13-start-menu-design.md`

## Global Constraints

- GDScript only, static typing throughout (typed vars/params/returns) — CLAUDE.md §2.
- `PascalCase` classes, `snake_case` script files/methods.
- No placeholder/TBD code; every step below is complete, runnable GDScript.
- `Continue` is a permanent, always-disabled placeholder — no save system exists, none is built
  here.
- `seed_demo_party()`'s existing `pc_override == null` behavior must remain byte-for-byte identical
  to today (every existing call site passes no argument) — this is a strict regression constraint,
  not just a nice-to-have.
- A freshly created PC passed as `pc_override` gets `level = 4` forced — `[ASSUMPTION]`,
  playtest-only, per the spec's explicit "unlock each class's early kit for this playtest round"
  request.
- The companion-bench loop must exclude `pc.class_id` (dynamic) instead of the literal `&"warrior"`
  it hardcodes today — required by the generalization, not optional polish.
- This plan reverses a previously-locked decision (`main_scene == town_demo.tscn`, enforced by
  `tests/test_main_scene_is_town_demo.gd`) with the player's explicit go-ahead — the old test is
  updated/renamed, not left in place alongside a contradictory new one.
- The Godot executable lives ONE DIRECTORY ABOVE this repo:
  `C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe` (repo root is
  `C:/bunnies/bunnies-main/bunnies`). Run tests with:
  `"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_<name>.gd`
  Exit code `0` = pass. Harmless `RID allocations leaked` / `ObjectDB instances leaked` warnings at
  process exit are pre-existing noise in this project's headless runs, not failures.
- **Known project gotcha:** after adding a new `class_name`, Godot's `--headless --script` runner
  can require a one-time class-cache refresh before it resolves it:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`. If this happens, use
  the refresh — never a `preload()`/untyped-variable workaround, which breaks static typing.
- Never delete `.godot/` to troubleshoot a test failure (gitignored, but wipes the project-wide
  `class_name` registry).
- Stage and commit only the files each task actually touches — this repo currently has several
  unrelated pre-existing untracked files sitting in the working tree; do not sweep them into a
  commit with a broad `git add`.

---

### Task 1: Generalize `InventoryDemoSetup.seed_demo_party()` around an optional real PC

**Files:**
- Modify: `world/inventory_demo_setup.gd`
- Test: `tests/test_inventory_demo_setup_pc_override.gd`

**Interfaces:**
- Consumes: `ClassLibrary.IDS`/`ClassLibrary.make(id) -> CharacterClass` (pre-existing),
  `CharacterClass.build_combatant(is_player: bool) -> Combatant` (pre-existing), `Combatant.class_id`
  (pre-existing), `Combatant.level` (pre-existing, setter clamps to `[1, 10]`).
- Produces: `InventoryDemoSetup.seed_demo_party(pc_override: Combatant = null) -> Dictionary`
  (signature CHANGE — was `seed_demo_party() -> Dictionary`, no existing call site passes an
  argument today so this is purely additive/backward-compatible).

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_demo_setup_pc_override.gd`:

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

func _init() -> void:
	# Regression: the null path (every existing call site) is byte-for-byte unchanged.
	var default_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
	var default_pc: Combatant = default_seed["pc"]
	_check(default_pc.display_name == "Martin", "null path: default pc is still 'Martin' (got '%s')" % default_pc.display_name)
	_check(default_pc.level == 9, "null path: default pc is still level 9 (got %d)" % default_pc.level)
	_check(default_pc.class_id == &"warrior", "null path: default pc is still a Warrior")
	var default_bench: Array = default_seed["bench"]
	_check(default_bench.size() == 5, "null path: bench still excludes exactly warrior+skirmisher (got %d)" % default_bench.size())
	for recruit: Combatant in default_bench:
		_check(recruit.class_id != &"warrior" and recruit.class_id != &"skirmisher", "null path: bench never contains warrior or skirmisher")

	# pc_override path: a real created PC (a Vanguard, distinct from the companion's Skirmisher and
	# from the default Warrior) is used as-is, forced to level 4, and the bench-exclusion bug is fixed.
	var created_pc: Combatant = ClassLibrary.make(&"vanguard").build_combatant(true)
	created_pc.display_name = "Rose"
	created_pc.level = 1
	var overridden_seed: Dictionary = InventoryDemoSetup.seed_demo_party(created_pc)
	var seeded_pc: Combatant = overridden_seed["pc"]
	_check(seeded_pc == created_pc, "pc_override path: the SAME Combatant instance is returned as 'pc', not a copy")
	_check(seeded_pc.display_name == "Rose", "pc_override path: the created pc's own name is preserved")
	_check(seeded_pc.level == 4, "pc_override path: level is forced to 4 for this playtest (got %d)" % seeded_pc.level)

	var companions: Array = overridden_seed["companions"]
	_check(companions.size() == 1 and companions[0].display_name == "Basil" and companions[0].class_id == &"skirmisher", "pc_override path: companion Basil (Skirmisher) is unchanged")

	var bench: Array = overridden_seed["bench"]
	_check(bench.size() == 5, "pc_override path: bench excludes exactly vanguard+skirmisher, 5 of the other 5 classes remain (got %d)" % bench.size())
	var bench_class_ids: Array = []
	for recruit: Combatant in bench:
		bench_class_ids.append(recruit.class_id)
	_check(&"warrior" in bench_class_ids, "BUG FIX: bench now correctly includes Warrior when the PC is NOT a Warrior (previously always excluded)")
	_check(not (&"vanguard" in bench_class_ids), "bench correctly excludes the PC's own class (Vanguard)")
	_check(not (&"skirmisher" in bench_class_ids), "bench still correctly excludes the companion's class (Skirmisher)")

	print(("INVENTORY DEMO SETUP PC OVERRIDE TEST PASSED" if _failures == 0 else "INVENTORY DEMO SETUP PC OVERRIDE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_inventory_demo_setup_pc_override.gd
```
Expected: a parse/argument error (`seed_demo_party()` doesn't accept an argument yet) or failures on
the bench-exclusion assertions — non-zero exit code.

- [ ] **Step 3: Edit `world/inventory_demo_setup.gd`**

Replace the method's opening (originally lines 10-28, up through the bench-building loop) with:

```gdscript
static func seed_demo_party(pc_override: Combatant = null) -> Dictionary:
	var pc: Combatant
	if pc_override != null:
		pc = pc_override
		pc.level = 4   # [ASSUMPTION] playtest-only: unlocks each class's early ability kit immediately
	else:
		pc = ClassLibrary.make(&"warrior").build_combatant(true)
		pc.display_name = "Martin"
		pc.level = 9   # can equip every rarity tier, so the demo can show the full ladder

	var companion: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	companion.display_name = "Basil"
	companion.level = 3   # can equip Common/Uncommon only — exercises a visible level-gate rejection

	# Precreated companion bench (2026-07-12 Party Selection work) — one per remaining class
	# (everything except the PC's own class and the already-in-party Skirmisher/Basil), all at
	# level 3 like Basil — base ability + Ultimate only, no L5/L7/L9 kit, per player direction.
	# Excludes pc.class_id (not a hardcoded &"warrior") since pc can now be ANY class, via
	# pc_override (2026-08-13 start-menu spec) — a hardcoded &"warrior" exclusion would wrongly keep
	# excluding Warrior and wrongly include a duplicate of whatever class the real PC actually is.
	var bench: Array[Combatant] = []
	for class_id: StringName in ClassLibrary.IDS:
		if class_id == pc.class_id or class_id == &"skirmisher":
			continue
		var recruit: Combatant = ClassLibrary.make(class_id).build_combatant(true)
		recruit.level = 3
		bench.append(recruit)
```

Leave every line after the bench-building loop (the `inv`/`vault`/gear/weapon/potion setup and the
final `return { ... }` block) exactly as it is — this task does not touch that part of the file.

- [ ] **Step 4: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`,
`INVENTORY DEMO SETUP PC OVERRIDE TEST PASSED`, no `FAIL:` lines.

- [ ] **Step 5: Run the existing equipment/inventory demo tests for regressions**

`seed_demo_party()`'s null path must be unchanged — confirm nothing that depends on today's demo
party broke:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_talents.gd
```
Expected: exit code `0` (this file exercises `town_demo.tscn`'s default no-`CombatHandoff` boot
path, which calls `seed_demo_party()` with no argument).

- [ ] **Step 6: Commit**

```bash
git add world/inventory_demo_setup.gd tests/test_inventory_demo_setup_pc_override.gd
git commit -m "feat(start-menu): generalize seed_demo_party() around an optional real PC"
```

---

### Task 2: `StartMenu` scene — New Game / Continue / Quit, wired to character creation

**Files:**
- Create: `world/start_menu.gd`
- Create: `world/start_menu.tscn`
- Test: `tests/test_start_menu.gd`

**Interfaces:**
- Consumes: `CharacterCreationScreen` + its `character_created(pc: Combatant)` signal and its
  `select_species_for_test(id)`/`select_class_for_test(id)`/`select_background_for_test(id)`/
  `enter_name_for_test(text)`/`press_next_for_test()` test hooks (all pre-existing, unchanged),
  `InventoryDemoSetup.seed_demo_party(pc_override: Combatant) -> Dictionary` (Task 1), the
  `CombatHandoff` autoload's `pc`/`companions`/`bench`/`party_inventory`/`vault` fields
  (pre-existing), `TownDemo` (pre-existing, referenced only by test for a type check).
- Produces: `StartMenu` class; test hooks `press_new_game_for_test()`,
  `creation_screen_for_test() -> CharacterCreationScreen`, `press_continue_for_test()`,
  `continue_disabled_for_test() -> bool`, `press_quit_for_test()` — nothing later consumes these
  since this is the plan's final production task (Task 3 only touches config/tests).

- [ ] **Step 1: Write the failing test**

Create `tests/test_start_menu.gd`:

```gdscript
extends SceneTree

## Scene-level test for StartMenu (spec 2026-08-13-start-menu-design.md). Drives New Game and the
## full Species->Class->Background->Name->Finalize walkthrough via real signals/button presses (the
## same CharacterCreationScreen test hooks its own test file uses), then confirms CombatHandoff is
## populated and the scene actually transitions to town_demo.tscn. Does NOT press Quit — that calls
## get_tree().quit(), which would terminate this test process; wiring is confirmed by inspection
## instead (see the final checks).

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/start_menu.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var menu: StartMenu = _instance

		_check(menu.continue_disabled_for_test(), "Continue is permanently disabled (no save system exists)")

		menu.press_new_game_for_test()
		var screen: CharacterCreationScreen = menu.creation_screen_for_test()
		_check(screen != null, "pressing New Game instances a real CharacterCreationScreen")

		screen.select_species_for_test(&"hare")
		screen.press_next_for_test()
		screen.select_class_for_test(&"vanguard")
		screen.press_next_for_test()
		screen.select_background_for_test(&"abbey_cook")
		screen.press_next_for_test()
		screen.enter_name_for_test("Rose")
		screen.press_next_for_test()   # Finalize -> emits character_created

		var handoff: Node = get_node("/root/CombatHandoff")
		_check(handoff.pc != null, "Finalize populates CombatHandoff.pc")
		_check(handoff.pc.display_name == "Rose", "CombatHandoff.pc carries the created PC's name")
		_check(handoff.pc.level == 4, "CombatHandoff.pc's level was forced to 4 by seed_demo_party()")
		_check(handoff.companions.size() == 1, "CombatHandoff.companions carries the seeded companion (Basil)")
		_check(handoff.bench.size() == 5, "CombatHandoff.bench carries the seeded bench (excludes Vanguard+Skirmisher)")
		_check(handoff.party_inventory != null, "CombatHandoff.party_inventory is populated")
		_check(handoff.vault != null, "CombatHandoff.vault is populated")

	if _frames >= 4:
		var current: Node = get_tree().current_scene
		_check(current is TownDemo, "the scene actually transitioned to town_demo.tscn after Finalize")
		print("ok start-menu scene test complete")
		if current != null:
			current.free()
		return true
	return false
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_start_menu.gd
```
Expected: a load error (`res://world/start_menu.tscn` doesn't exist yet) — non-zero exit code.

- [ ] **Step 3: Create `world/start_menu.gd`**

```gdscript
class_name StartMenu
extends Control

## The game's boot screen (spec 2026-08-13-start-menu-design.md). New Game launches
## CharacterCreationScreen as a full-screen child (hiding the menu buttons underneath), seeds the
## rest of the demo party around the created PC via InventoryDemoSetup.seed_demo_party(pc),
## populates CombatHandoff, then transitions to town_demo.tscn -- whose existing
## "handoff.pc != null" fallback already handles the rest, unchanged. Continue is a permanent
## placeholder (no save system exists yet). Built entirely in code (only the root Control lives in
## start_menu.tscn), matching this project's screen/panel convention.

var _new_game_button: Button
var _continue_button: Button
var _quit_button: Button
var _creation_screen: CharacterCreationScreen

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_new_game_button = Button.new()
	_new_game_button.text = "New Game"
	_new_game_button.position = Vector2(24, 24)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	add_child(_new_game_button)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(24, 64)
	_continue_button.disabled = true
	add_child(_continue_button)

	_quit_button = Button.new()
	_quit_button.text = "Quit"
	_quit_button.position = Vector2(24, 104)
	_quit_button.pressed.connect(_on_quit_pressed)
	add_child(_quit_button)

func _on_new_game_pressed() -> void:
	_new_game_button.visible = false
	_continue_button.visible = false
	_quit_button.visible = false

	_creation_screen = CharacterCreationScreen.new()
	_creation_screen.character_created.connect(_on_character_created)
	add_child(_creation_screen)

func _on_character_created(pc: Combatant) -> void:
	var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party(pc)
	var handoff: Node = get_node("/root/CombatHandoff")
	handoff.pc = party_seed["pc"]
	handoff.companions = party_seed["companions"]
	handoff.bench = party_seed["bench"]
	handoff.party_inventory = party_seed["party_inventory"]
	handoff.vault = party_seed["vault"]
	get_tree().change_scene_to_file("res://world/town_demo.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

# --- headless test hooks ---

func press_new_game_for_test() -> void:
	_new_game_button.pressed.emit()

func creation_screen_for_test() -> CharacterCreationScreen:
	return _creation_screen

func press_continue_for_test() -> void:
	_continue_button.pressed.emit()

func continue_disabled_for_test() -> bool:
	return _continue_button.disabled

func press_quit_for_test() -> void:
	_quit_button.pressed.emit()
```

- [ ] **Step 4: Create `world/start_menu.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://world/start_menu.gd" id="1_start_menu"]

[node name="StartMenu" type="Control"]
script = ExtResource("1_start_menu")
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `ok start-menu scene test complete`, no
`FAIL` lines. (If a fresh `class_name` fails to resolve, run the class-cache refresh from Global
Constraints, then retry — do not work around it with `preload()`.)

- [ ] **Step 6: Commit**

```bash
git add world/start_menu.gd world/start_menu.tscn tests/test_start_menu.gd
git commit -m "feat(start-menu): add StartMenu scene wired to character creation"
```

---

### Task 3: Make `start_menu.tscn` the boot scene

**Files:**
- Modify: `project.godot`
- Delete: `tests/test_main_scene_is_town_demo.gd`
- Create: `tests/test_main_scene_is_start_menu.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing consumed by any other task — this is the plan's final task.

- [ ] **Step 1: Write the failing test**

Create `tests/test_main_scene_is_start_menu.gd`:

```gdscript
extends SceneTree

## Headless test locking in the project's boot scene (2026-08-13 start-menu spec) -- supersedes the
## 2026-08-10 decision (tests/test_main_scene_is_town_demo.gd, now deleted) that main_scene must be
## town_demo.tscn. A real StartMenu now exists and owns the "New Game" path into town_demo.tscn via
## CharacterCreationScreen + InventoryDemoSetup.seed_demo_party(pc), so the exported build's entry
## point is the start menu, not the town directly.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_scene == "res://world/start_menu.tscn", "main_scene is start_menu.tscn (got: %s)" % main_scene)

	print(("MAIN SCENE IS START MENU TEST PASSED" if _failures == 0 else "MAIN SCENE IS START MENU TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_main_scene_is_start_menu.gd
```
Expected: `FAIL: main_scene is start_menu.tscn (got: res://world/town_demo.tscn)` — non-zero exit
code.

- [ ] **Step 3: Change `project.godot`'s `main_scene` setting**

Find the line:
```
run/main_scene="res://world/town_demo.tscn"
```
Change it to:
```
run/main_scene="res://world/start_menu.tscn"
```

- [ ] **Step 4: Delete the superseded test**

```bash
git rm tests/test_main_scene_is_town_demo.gd
```

- [ ] **Step 5: Run the new test to verify it passes**

Run the same command as Step 2. Expected: exit code `0`, `MAIN SCENE IS START MENU TEST PASSED`.

- [ ] **Step 6: Run the full set of this plan's tests together, plus Task 2's, for a final regression pass**

```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_inventory_demo_setup_pc_override.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_start_menu.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_main_scene_is_start_menu.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_talents.gd
```
Expected: exit code `0` on all 4.

- [ ] **Step 7: Commit**

```bash
git add project.godot tests/test_main_scene_is_start_menu.gd
git commit -m "feat(start-menu): make start_menu.tscn the boot scene, superseding the 2026-08-10 lock"
```

---

## Plan Self-Review Notes

- **Spec coverage:** Scene structure/boot flow (Task 2 + Task 3), New Game flow incl. Combatant
  handoff (Task 2), `seed_demo_party()` generalization + the level-4/bench-exclusion fix (Task 1),
  `main_scene` reversal + its test (Task 3). Testing section's 3 bullets map 1:1 to Tasks 1-3.
- **Placeholder scan:** no TBD/TODO markers; every code block is complete and runnable.
- **Type consistency:** `InventoryDemoSetup.seed_demo_party(pc_override: Combatant = null)` (Task 1)
  is called identically in Task 2's `_on_character_created()`. `StartMenu`'s test-hook names (Task 2)
  are used identically in its own test only — no later task depends on them.
- **Out of scope, confirmed untouched by any task:** any save/load system, any intro
  cutscene/tutorial entry point, the Class Trial & Lock-In mechanic.
