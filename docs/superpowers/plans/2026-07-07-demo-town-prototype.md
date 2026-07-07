# First Playable Town (Demo) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a throwaway demo town scene proving the movement/interaction/scene-architecture
convention for out-of-combat play — free-continuous PC movement, wandering NPCs, a walk-in shop with
no load screen, and an Adventuring Board — per
`docs/superpowers/specs/2026-07-07-demo-town-prototype-design.md`.

**Architecture:** One pre-loaded `Node2D` scene (`world/town_demo.tscn` + `world/town_demo.gd`) built
entirely in code, mirroring how `combat.tscn`/`combat.gd` work today (a near-empty `.tscn`, everything
constructed in `_ready()`). A reusable `Interactable` component (an `Area2D`, used either as a
scene root for stationary things or as a child node for moving things) backs doors, wandering
villagers, and the Adventuring Board. Dialogue and quest-board content are small `Resource` types,
matching this project's existing `Weapon`/`Effect`/`ReelFace` convention.

**Tech Stack:** Godot 4.6.3-stable, GDScript only, no C#, no third-party addons, no autoloads (none
exist in this project and none are needed here).

## Global Constraints

- **Godot 4.6.3-stable**, `Forward Plus` renderer, project root = `C:\bunnies\bunnies-main\bunnies`
  (contains `project.godot`). The engine executable is one level up:
  `C:\Bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`.
- **GDScript only.** Static typing everywhere — every `var`/`func` parameter/return gets an explicit
  type (`CLAUDE.md` §2).
- **Signals are past-tense, no `on_` prefix** on the signal itself; handlers are named
  `_on_<emitter>_<signal>` (`CLAUDE.md` §2). New signals in this plan: `interacted`, `dialogue_requested`,
  `board_opened`, `entry_selected`, `closed`.
- **Data as Resources.** `DialogueLine`, `DialogueSet`, `QuestBoardEntry` are `Resource` subclasses with
  flat `@export var` fields and a `##` doc comment per field, matching `combat/resources/reel_face.gd`
  / `combat/resources/ability_def.gd` exactly — no `_init()` constructors on these, plain field defaults.
- **UI is built in code, not authored in the `.tscn` editor** — matches `combat/ui/ability_menu_panel.gd`
  (a `Panel` built entirely via `add_child()` calls in a method, no companion scene file). New `.tscn`
  files in this plan (`world/town_demo.tscn`) stay minimal: a root node with a script attached, nothing
  else, matching `combat/combat.tscn`.
- **No test framework exists.** Every test file `extends SceneTree`, does its work in `_init()`, defines
  its own local `_check(cond: bool, label: String) -> void` helper that prints `"ok " + label` or
  `"FAIL " + label`, and ends with a bare `quit()`. There is no `assert()` anywhere in `tests/` — don't
  introduce one. This is the **newest** convention in the repo (e.g. `tests/test_extra_ability_ultimate_conflict.gd`,
  2026-07-07) — match it exactly, not the older `_initialize()`/`push_error` variant.
- **Test run command** (from the Bash cwd `C:\bunnies\bunnies-main\bunnies`):
  ```bash
  GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
  "$GODOT" --headless --path . --script res://tests/test_<name>.gd
  ```
- **After adding ANY brand-new `class_name`**, refresh the class cache once before the next `--script`
  run, or Godot can't resolve the new class:
  ```bash
  "$GODOT" --headless --path . --editor --quit
  ```
- **This codebase has zero prior `CharacterBody2D`/`Area2D`/`Camera2D`/`Node2D`/`YSort` usage.** Every
  physics/2D-world line in this plan is new territory for the project — write it in full, don't assume
  an existing pattern to lean on beyond what's spelled out here.
- **No content commitment.** All town content (NPC lines, quest rows, layout coordinates) is disposable
  placeholder data. What must be right is the movement/interaction/scene-architecture pattern.
- **Movement/interaction *feel* is a manual playtest call, not a testable claim** (`CLAUDE.md` §5 hard
  ceiling) — only pure-logic pieces (state transitions, grouping, bounds math) get automated tests.
- Never commit `.gd.uid` files by hand — Godot auto-generates them on first parse; don't create them
  yourself and don't worry if `git status` shows them appearing after a test run.

---

## File Structure

| File | Responsibility |
|---|---|
| `world/setup_input_map.gd` | One-off generator: writes the project's first-ever Input Map actions (movement + interact) into `project.godot`. |
| `world/resources/dialogue_line.gd` | `DialogueLine` — one line of dialogue (speaker + text). Data only. |
| `world/resources/dialogue_set.gd` | `DialogueSet` — an ordered list of `DialogueLine`s. Data only. |
| `world/resources/quest_board_entry.gd` | `QuestBoardEntry` — one Adventuring Board row (title/category/body). Data only. |
| `world/ui/dialogue_box.gd` | `DialogueBox` — line-by-line dialogue UI + its pure advance/finish logic. |
| `world/ui/adventuring_board_panel.gd` | `AdventuringBoardPanel` — grouped selectable quest rows, styled after `AbilityMenuPanel`. |
| `world/ui/interact_prompt.gd` | `InteractPrompt` — tiny show/hide prompt label. |
| `world/interactable.gd` | `Interactable` — the shared Area2D interaction component + nearest-selection logic. |
| `world/door.gd` | `Door` — building entry/exit, no load screen. |
| `world/pc_controller.gd` | `PCController` — the PC's free-continuous movement + interaction-reach tracking. |
| `world/villager.gd` | `Villager` — wandering NPC (also used, non-wandering, as the Shopkeeper). |
| `world/adventuring_board.gd` | `AdventuringBoard` — the board landmark, opens `AdventuringBoardPanel`. |
| `world/town_demo.tscn` / `world/town_demo.gd` | Root scene: builds the plaza, the shop interior, and wires everything together. |
| `tests/test_dialogue_set.gd`, `test_dialogue_box.gd`, `test_quest_board_entry.gd`, `test_adventuring_board_panel.gd`, `test_interactable.gd`, `test_door_transition.gd`, `test_interact_prompt.gd`, `test_villager_wander.gd`, `test_adventuring_board.gd` | Headless coverage for every pure-logic piece above. |

---

### Task 1: Input Map setup

This project has **no `[input]` section in `project.godot` at all** — this is the first one. Hand-writing
the raw `InputEventKey` resource syntax is error-prone (it serializes as raw platform keycodes, not
symbolic names), so this task uses a one-off script that calls Godot's own `InputMap`/`ProjectSettings`
APIs to generate it correctly — the same spirit as this project's existing `gen_damage_types.gd`
generator script (`CLAUDE.md`'s type-chart section).

**Files:**
- Create: `world/setup_input_map.gd`
- Modify: `project.godot` (generated by running the script below — do not hand-edit)

**Interfaces:**
- Produces: the Input Map actions `move_up`, `move_down`, `move_left`, `move_right`, `interact` —
  every later task that reads `Input.get_action_strength(...)` or `Input.is_action_just_pressed(...)`
  depends on these exact names existing.

- [ ] **Step 1: Write the generator script**

```gdscript
extends SceneTree

## One-off generator for this project's first Input Map actions (2026-07-07-demo-town-prototype-design.md).
## Run once via `--script`; safe to re-run (it clears and rewrites each action's events).

func _add_action(action_name: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		InputMap.action_erase_event(action_name, existing_event)
	for keycode in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action_name, event)
	var events: Array = []
	for event2 in InputMap.action_get_events(action_name):
		events.append(event2)
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": 0.5, "events": events})

func _init() -> void:
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("interact", [KEY_E])
	var save_error: Error = ProjectSettings.save()
	print("input map saved with error code: ", save_error)
	quit()
```

- [ ] **Step 2: Run the generator**

```bash
GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
"$GODOT" --headless --path . --script res://world/setup_input_map.gd
```
Expected output: `input map saved with error code: 0`

- [ ] **Step 3: Verify `project.godot` now has an `[input]` section**

```bash
grep -n "^\[input\]" project.godot
grep -n "^move_up=" project.godot
grep -n "^interact=" project.godot
```
Expected: all three greps find a match.

- [ ] **Step 4: Commit**

```bash
git add world/setup_input_map.gd project.godot
git commit -m "feat(world): generate the project's first Input Map actions for town movement"
```

---

### Task 2: DialogueLine + DialogueSet resources

**Files:**
- Create: `world/resources/dialogue_line.gd`
- Create: `world/resources/dialogue_set.gd`
- Test: `tests/test_dialogue_set.gd`

**Interfaces:**
- Produces: `DialogueLine.speaker_name: String`, `DialogueLine.text: String`;
  `DialogueSet.lines: Array[DialogueLine]`, `DialogueSet.line_count() -> int`. Task 3 (`DialogueBox`)
  and Task 11 (`town_demo.gd`) both construct and read these directly.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var line := DialogueLine.new()
	line.speaker_name = "Villager"
	line.text = "Hello there!"
	_check(line.speaker_name == "Villager", "DialogueLine.speaker_name settable")
	_check(line.text == "Hello there!", "DialogueLine.text settable")

	var farewell := DialogueLine.new()
	farewell.speaker_name = "Villager"
	farewell.text = "Safe travels!"

	var lines: Array[DialogueLine] = [line, farewell]
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	_check(dialogue_set.line_count() == 2, "DialogueSet.line_count reflects assigned lines")
	_check(dialogue_set.lines[0] == line, "DialogueSet.lines preserves order (index 0)")
	_check(dialogue_set.lines[1] == farewell, "DialogueSet.lines preserves order (index 1)")

	var empty_set := DialogueSet.new()
	_check(empty_set.line_count() == 0, "DialogueSet defaults to zero lines")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
"$GODOT" --headless --path . --script res://tests/test_dialogue_set.gd
```
Expected: an error that `DialogueLine`/`DialogueSet` do not exist (parse/identifier error), since
neither class exists yet.

- [ ] **Step 3: Write `DialogueLine`**

```gdscript
class_name DialogueLine
extends Resource

## One line of dialogue (2026-07-07-demo-town-prototype-design.md §6). Data only —
## the advance/finish state machine lives in DialogueBox, not here.

## Who's speaking this line. Shown as-is in the DialogueBox's name label.
@export var speaker_name: String = ""

## The line's text. Shown as-is in the DialogueBox's text label.
@export var text: String = ""
```

- [ ] **Step 4: Write `DialogueSet`**

```gdscript
class_name DialogueSet
extends Resource

## An ordered set of DialogueLines played back by DialogueBox (spec §6). Data only.

## Played back in order, index 0 first. Empty means "nothing to say" — DialogueBox
## should not be opened with an empty set.
@export var lines: Array[DialogueLine] = []

## Convenience accessor so callers don't reach into `lines.size()` directly.
func line_count() -> int:
	return lines.size()
```

- [ ] **Step 5: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 6: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_dialogue_set.gd
```
Expected: five `ok ...` lines, no `FAIL`.

- [ ] **Step 7: Commit**

```bash
git add world/resources/dialogue_line.gd world/resources/dialogue_set.gd tests/test_dialogue_set.gd
git commit -m "feat(world): add DialogueLine/DialogueSet resources"
```

---

### Task 3: DialogueBox

**Files:**
- Create: `world/ui/dialogue_box.gd`
- Test: `tests/test_dialogue_box.gd`

**Interfaces:**
- Consumes: `DialogueSet.lines: Array[DialogueLine]` (Task 2).
- Produces: `DialogueBox.open(dialogue_set: DialogueSet) -> void`, `DialogueBox.advance() -> void`,
  `DialogueBox.is_open() -> bool`, `DialogueBox.close() -> void`, signal `closed`. Task 9 (`Villager`)
  and Task 11 (`town_demo.gd`) call `open()`/`advance()`/`is_open()` directly.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_two_line_set() -> DialogueSet:
	var first := DialogueLine.new()
	first.speaker_name = "Villager"
	first.text = "Hello!"
	var second := DialogueLine.new()
	second.speaker_name = "Villager"
	second.text = "Goodbye!"
	var lines: Array[DialogueLine] = [first, second]
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	return dialogue_set

func _init() -> void:
	var dialogue_set := _make_two_line_set()

	# Pure static logic first — no node/tree involved.
	_check(not DialogueBox.is_finished(dialogue_set, 0), "index 0 is not finished (2-line set)")
	_check(not DialogueBox.is_finished(dialogue_set, 1), "index 1 is not finished (2-line set)")
	_check(DialogueBox.is_finished(dialogue_set, 2), "index 2 IS finished (2-line set)")
	_check(DialogueBox.line_at(dialogue_set, 0).text == "Hello!", "line_at(0) returns the first line")
	_check(DialogueBox.line_at(dialogue_set, 1).text == "Goodbye!", "line_at(1) returns the second line")

	# Instance behavior — built via .new(), never added to a live tree (matches
	# AbilityMenuPanel's test convention: construction logic lives in open(), not _ready()).
	var box := DialogueBox.new()
	_check(not box.is_open(), "DialogueBox starts closed")

	box.open(dialogue_set)
	_check(box.is_open(), "open() shows the box")
	_check(box.current_speaker_for_test() == "Villager", "open() renders the first line's speaker")
	_check(box.current_text_for_test() == "Hello!", "open() renders the first line's text")

	box.advance_for_test()
	_check(box.is_open(), "advancing to the last line keeps the box open")
	_check(box.current_text_for_test() == "Goodbye!", "advance() renders the second line's text")

	# GDScript lambdas capture outer locals BY VALUE, so a plain `var closed_fired: bool`
	# assigned inside the lambda never propagates out. Route it through a one-element
	# array instead — the standard GDScript capture workaround.
	var closed_fired: Array[bool] = [false]
	box.closed.connect(func() -> void: closed_fired[0] = true)
	box.advance_for_test()
	_check(not box.is_open(), "advancing past the last line closes the box")
	_check(closed_fired[0], "closing emits the closed signal")
	box.free()  # never entered the tree, so free manually (matches test_ability_menu_panel.gd)
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_dialogue_box.gd
```
Expected: an identifier error — `DialogueBox` does not exist yet.

- [ ] **Step 3: Write `DialogueBox`**

```gdscript
class_name DialogueBox
extends Panel

## Line-by-line dialogue UI (spec §6). Built entirely in code (matches
## combat/ui/ability_menu_panel.gd's convention) — construction lives in _init(), not
## _ready(), so the box works whether or not it's ever added to a live scene tree
## (required for headless testing, same reasoning as AbilityMenuPanel).

signal closed

var _dialogue_set: DialogueSet
var _index: int = 0
var _name_label: Label
var _text_label: Label

## True once `index` has advanced past the set's last line. Pure/static so it's
## unit-testable without an instance.
static func is_finished(dialogue_set: DialogueSet, index: int) -> bool:
	return index >= dialogue_set.line_count()

## The line at `index`. Callers must check is_finished() first — this does not bounds-check.
static func line_at(dialogue_set: DialogueSet, index: int) -> DialogueLine:
	return dialogue_set.lines[index]

func _init() -> void:
	_name_label = Label.new()
	_name_label.position = Vector2(16, 8)
	add_child(_name_label)

	_text_label = Label.new()
	_text_label.position = Vector2(16, 32)
	_text_label.custom_minimum_size = Vector2(560, 60)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_text_label)

	hide()

func open(dialogue_set: DialogueSet) -> void:
	_dialogue_set = dialogue_set
	_index = 0
	_render_current()
	show()

func advance() -> void:
	_index += 1
	if is_finished(_dialogue_set, _index):
		close()
	else:
		_render_current()

func close() -> void:
	hide()
	closed.emit()

func is_open() -> bool:
	return visible

func _render_current() -> void:
	var line: DialogueLine = line_at(_dialogue_set, _index)
	_name_label.text = line.speaker_name
	_text_label.text = line.text

## --- Headless test hooks (mirrors AbilityMenuPanel's press_row_for_test convention) ---

func current_speaker_for_test() -> String:
	return _name_label.text

func current_text_for_test() -> String:
	return _text_label.text

func advance_for_test() -> void:
	advance()
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_dialogue_box.gd
```
Expected: thirteen `ok ...` lines, no `FAIL` (the brief undercounted this when first written — trust the
test code's actual `_check()` calls, confirmed during Task 3's implementation).

- [ ] **Step 6: Commit**

```bash
git add world/ui/dialogue_box.gd tests/test_dialogue_box.gd
git commit -m "feat(world): add DialogueBox with static advance/finish logic"
```

---

### Task 4: QuestBoardEntry resource

**Files:**
- Create: `world/resources/quest_board_entry.gd`
- Test: `tests/test_quest_board_entry.gd`

**Interfaces:**
- Produces: `QuestBoardEntry.Category` enum (`CURRENT`, `SIDE`, `RECAP`), `QuestBoardEntry.title: String`,
  `QuestBoardEntry.category: Category`, `QuestBoardEntry.body_text: String`. Task 5
  (`AdventuringBoardPanel`) and Task 10 (`AdventuringBoard`) both consume these fields.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var entry := QuestBoardEntry.new()
	_check(entry.category == QuestBoardEntry.Category.CURRENT, "category defaults to CURRENT")
	entry.title = "Clear the Cellar"
	entry.category = QuestBoardEntry.Category.SIDE
	entry.body_text = "Coming soon."
	_check(entry.title == "Clear the Cellar", "title settable")
	_check(entry.category == QuestBoardEntry.Category.SIDE, "category settable")
	_check(entry.body_text == "Coming soon.", "body_text settable")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_quest_board_entry.gd
```
Expected: an identifier error — `QuestBoardEntry` does not exist yet.

- [ ] **Step 3: Write `QuestBoardEntry`**

```gdscript
class_name QuestBoardEntry
extends Resource

## One row on the town's Adventuring Board (spec §7). Every row in the 2026-07-07 demo is a
## blank placeholder — no real quest content or tracking exists yet.

enum Category { CURRENT, SIDE, RECAP }

@export var title: String = ""
@export var category: Category = Category.CURRENT
@export var body_text: String = ""
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_quest_board_entry.gd
```
Expected: four `ok ...` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/resources/quest_board_entry.gd tests/test_quest_board_entry.gd
git commit -m "feat(world): add QuestBoardEntry resource"
```

---

### Task 5: AdventuringBoardPanel

**Files:**
- Create: `world/ui/adventuring_board_panel.gd`
- Test: `tests/test_adventuring_board_panel.gd`

**Interfaces:**
- Consumes: `QuestBoardEntry.title/category/body_text` (Task 4).
- Produces: `AdventuringBoardPanel.open_for(entries: Array[QuestBoardEntry]) -> void`,
  `AdventuringBoardPanel.close() -> void`, signal `entry_selected(entry: QuestBoardEntry)`. Task 10
  (`AdventuringBoard`) and Task 11 (`town_demo.gd`) call `open_for()`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_entry(title: String, category: QuestBoardEntry.Category, body: String) -> QuestBoardEntry:
	var entry := QuestBoardEntry.new()
	entry.title = title
	entry.category = category
	entry.body_text = body
	return entry

func _init() -> void:
	var current := _make_entry("Clear the Cellar", QuestBoardEntry.Category.CURRENT, "Coming soon.")
	var side := _make_entry("Lost Cat", QuestBoardEntry.Category.SIDE, "Coming soon.")
	var recap := _make_entry("How We Got Here", QuestBoardEntry.Category.RECAP, "Coming soon.")
	var entries: Array[QuestBoardEntry] = [current, side, recap]

	# Pure static grouping logic first — no node/tree involved.
	var groups: Dictionary = AdventuringBoardPanel.group_by_category(entries)
	_check(groups[QuestBoardEntry.Category.CURRENT].size() == 1, "one CURRENT entry grouped")
	_check(groups[QuestBoardEntry.Category.CURRENT][0] == current, "CURRENT group holds the right entry")
	_check(groups[QuestBoardEntry.Category.SIDE][0] == side, "SIDE group holds the right entry")
	_check(groups[QuestBoardEntry.Category.RECAP][0] == recap, "RECAP group holds the right entry")

	var empty_groups: Dictionary = AdventuringBoardPanel.group_by_category([])
	_check(empty_groups[QuestBoardEntry.Category.CURRENT].size() == 0, "empty input groups to empty buckets")

	# Instance behavior — built via .new(), never added to a live tree.
	var panel := AdventuringBoardPanel.new()
	panel.open_for(entries)
	_check(panel.visible, "open_for() shows the panel")

	# GDScript lambdas capture outer locals BY VALUE — a plain `var selected` reassigned
	# inside the lambda would never propagate out. Route it through a one-element array.
	var selected: Array[QuestBoardEntry] = [null]
	panel.entry_selected.connect(func(entry: QuestBoardEntry) -> void: selected[0] = entry)
	panel.press_row_for_test(0)
	_check(selected[0] == current, "pressing row 0 selects the first entry (CURRENT header comes first)")

	panel.close()
	_check(not panel.visible, "close() hides the panel")
	panel.free()  # never entered the tree, so free manually (matches test_ability_menu_panel.gd)
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_adventuring_board_panel.gd
```
Expected: an identifier error — `AdventuringBoardPanel` does not exist yet.

- [ ] **Step 3: Write `AdventuringBoardPanel`**

```gdscript
class_name AdventuringBoardPanel
extends Panel

## The Adventuring Board's UI (spec §7), styled after combat/ui/ability_menu_panel.gd:
## rows are rebuilt from scratch on every open_for() call (never cached), pure grouping
## logic is split into a static func for headless testability, and a press_row_for_test()
## hook drives it without a live mouse/renderer.

signal entry_selected(entry: QuestBoardEntry)

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 420.0
const DETAIL_H: float = 60.0
const CATEGORY_ORDER: Array = [
	QuestBoardEntry.Category.CURRENT,
	QuestBoardEntry.Category.SIDE,
	QuestBoardEntry.Category.RECAP,
]
const CATEGORY_LABELS: Dictionary = {
	QuestBoardEntry.Category.CURRENT: "Current Quests",
	QuestBoardEntry.Category.SIDE: "Side Quests",
	QuestBoardEntry.Category.RECAP: "Story Recap",
}

var _row_buttons: Array[Button] = []
var _detail_label: Label

## Groups entries by category, preserving CURRENT/SIDE/RECAP order within each bucket.
## Pure/static so it's unit-testable without building the panel.
static func group_by_category(entries: Array[QuestBoardEntry]) -> Dictionary:
	var groups: Dictionary = {
		QuestBoardEntry.Category.CURRENT: [],
		QuestBoardEntry.Category.SIDE: [],
		QuestBoardEntry.Category.RECAP: [],
	}
	for entry: QuestBoardEntry in entries:
		groups[entry.category].append(entry)
	return groups

func open_for(entries: Array[QuestBoardEntry]) -> void:
	for child in get_children():
		child.queue_free()
	_row_buttons.clear()

	var groups: Dictionary = group_by_category(entries)
	var y: float = PAD
	for category: QuestBoardEntry.Category in CATEGORY_ORDER:
		var header := Label.new()
		header.text = CATEGORY_LABELS[category]
		header.position = Vector2(PAD, y)
		add_child(header)
		y += ROW_H
		for entry: QuestBoardEntry in groups[category]:
			var btn := Button.new()
			btn.text = entry.title
			btn.position = Vector2(PAD, y)
			btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
			btn.pressed.connect(func() -> void: _select_entry(entry))
			add_child(btn)
			_row_buttons.append(btn)
			y += ROW_H

	_detail_label = Label.new()
	_detail_label.position = Vector2(PAD, y + PAD)
	_detail_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, DETAIL_H)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_detail_label)

	custom_minimum_size = Vector2(PANEL_W, y + PAD * 2.0 + DETAIL_H)
	size = custom_minimum_size
	show()

func close() -> void:
	hide()

func _select_entry(entry: QuestBoardEntry) -> void:
	_detail_label.text = entry.body_text
	entry_selected.emit(entry)

## --- Headless test hook ---

func press_row_for_test(index: int) -> void:
	_row_buttons[index].pressed.emit()
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_adventuring_board_panel.gd
```
Expected: eight `ok ...` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/ui/adventuring_board_panel.gd tests/test_adventuring_board_panel.gd
git commit -m "feat(world): add AdventuringBoardPanel with static category grouping"
```

---

### Task 6: Interactable base

**Files:**
- Create: `world/interactable.gd`
- Test: `tests/test_interactable.gd`

**Interfaces:**
- Produces: `Interactable` (`extends Area2D`) with `prompt_text: String`, `interaction_radius: float`,
  virtual `interact() -> void`, signal `interacted`, and `static func nearest(candidates: Array[Interactable], from_position: Vector2) -> Interactable`.
  Task 7 (`Door`), Task 8 (`PCController`), Task 9 (`Villager`), and Task 10 (`AdventuringBoard`) all
  depend on these exact names.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var a := Interactable.new()
	a.position = Vector2(0, 0)
	var b := Interactable.new()
	b.position = Vector2(100, 0)
	var c := Interactable.new()
	c.position = Vector2(10, 0)

	var candidates: Array[Interactable] = [a, b, c]
	var nearest_to_origin: Interactable = Interactable.nearest(candidates, Vector2(0, 0))
	_check(nearest_to_origin == a, "nearest() picks the closest candidate to the query point")

	var nearest_to_far_point: Interactable = Interactable.nearest(candidates, Vector2(95, 0))
	_check(nearest_to_far_point == b, "nearest() re-picks correctly for a different query point")

	var empty_candidates: Array[Interactable] = []
	_check(Interactable.nearest(empty_candidates, Vector2.ZERO) == null, "nearest() returns null for an empty list")

	# GDScript lambdas capture outer locals BY VALUE — a plain `var fired: bool` reassigned
	# inside the lambda would never propagate out. Route it through a one-element array.
	var fired: Array[bool] = [false]
	a.interacted.connect(func() -> void: fired[0] = true)
	a.interact()
	_check(fired[0], "default interact() emits the interacted signal")

	_check(a.prompt_text == "Interact", "prompt_text defaults to 'Interact'")
	a.prompt_text = "Talk"
	_check(a.prompt_text == "Talk", "prompt_text is settable")

	# a/b/c are Area2D (Node, not RefCounted) and were never added to a tree — free them
	# explicitly or the process reports leaked instances at exit.
	a.free()
	b.free()
	c.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_interactable.gd
```
Expected: an identifier error — `Interactable` does not exist yet.

- [ ] **Step 3: Write `Interactable`**

```gdscript
class_name Interactable
extends Area2D

## Base interaction hook for the demo town (spec §4). Stationary interactables (Door,
## AdventuringBoard) extend this directly and override interact(). Moving interactables
## (Villager) instead ADD a plain Interactable as a child node and connect to its
## `interacted` signal, since a CharacterBody2D can't also be an Area2D.
##
## Sets its own collision shape/layer in _ready() so every subclass and every composed
## child gets working overlap detection for free (layer 2 — see PCController's
## InteractionReach, which monitors that layer).

## Shown in the InteractPrompt UI whenever the PC's interaction reach overlaps this node.
@export var prompt_text: String = "Interact"

## Radius of the default collision circle created in _ready().
@export var interaction_radius: float = 16.0

## Emitted by the default interact() implementation. Subclasses that override interact()
## may skip emitting this if they don't need external listeners.
signal interacted

func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interaction_radius
	shape.shape = circle
	add_child(shape)

func interact() -> void:
	interacted.emit()

## Returns whichever candidate is closest to from_position, or null if candidates is
## empty. Pure/static so it's unit-testable without a live physics query.
static func nearest(candidates: Array[Interactable], from_position: Vector2) -> Interactable:
	var best: Interactable = null
	var best_dist: float = INF
	for candidate: Interactable in candidates:
		var dist: float = candidate.global_position.distance_squared_to(from_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_interactable.gd
```
Expected: six `ok ...` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/interactable.gd tests/test_interactable.gd
git commit -m "feat(world): add the Interactable component (nearest-selection + default interact())"
```

---

### Task 7: Door

**Files:**
- Create: `world/door.gd`
- Test: `tests/test_door_transition.gd`

**Interfaces:**
- Consumes: `Interactable` base (Task 6).
- Produces: `Door` (`extends Interactable`) with exported `current_area`/`target_area`/`entry_marker`/
  `camera`/`target_camera_limits`/`pc` fields, and `static func toggle_areas(current_area: Node2D, target_area: Node2D) -> void`.
  Task 11 (`town_demo.gd`) constructs two `Door` instances (entry + exit) for the shop.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var exterior := Node2D.new()
	exterior.visible = true
	exterior.process_mode = Node.PROCESS_MODE_INHERIT
	var interior := Node2D.new()
	interior.visible = false
	interior.process_mode = Node.PROCESS_MODE_DISABLED

	# Pure static toggle logic first.
	Door.toggle_areas(exterior, interior)
	_check(not exterior.visible, "toggle_areas hides the current area")
	_check(exterior.process_mode == Node.PROCESS_MODE_DISABLED, "toggle_areas disables the current area's processing")
	_check(interior.visible, "toggle_areas shows the target area")
	_check(interior.process_mode == Node.PROCESS_MODE_INHERIT, "toggle_areas re-enables the target area's processing")

	# Instance behavior — interact() wires toggle_areas + PC teleport + camera bounds.
	var pc := Node2D.new()
	pc.global_position = Vector2(999, 999)
	var entry_marker := Marker2D.new()
	entry_marker.global_position = Vector2(160, 180)
	var camera := Camera2D.new()

	var door := Door.new()
	door.current_area = exterior
	door.target_area = interior
	door.entry_marker = entry_marker
	door.camera = camera
	door.target_camera_limits = Rect2(0, 0, 320, 240)
	door.pc = pc

	door.interact()
	_check(not exterior.visible, "interact() hides the current area")
	_check(interior.visible, "interact() shows the target area")
	_check(pc.global_position == Vector2(160, 180), "interact() teleports the PC to the entry marker")
	_check(camera.limit_left == 0 and camera.limit_top == 0, "interact() sets the camera's top-left bound")
	_check(camera.limit_right == 320 and camera.limit_bottom == 240, "interact() sets the camera's bottom-right bound")

	# None of these Node-derived objects were ever added to a tree — free them explicitly
	# or the process reports leaked instances at exit.
	door.free()
	camera.free()
	entry_marker.free()
	pc.free()
	interior.free()
	exterior.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_door_transition.gd
```
Expected: an identifier error — `Door` does not exist yet.

- [ ] **Step 3: Write `Door`**

```gdscript
class_name Door
extends Interactable

## Building entry/exit with NO load screen (spec §3): same scene tree throughout, just a
## visibility/process toggle + PC teleport + camera-bounds swap. One script handles BOTH
## directions (shop entry AND shop exit) — town_demo.gd configures two instances of this
## same class with their current_area/target_area swapped.

@export var current_area: Node2D
@export var target_area: Node2D
@export var entry_marker: Marker2D
@export var camera: Camera2D
@export var target_camera_limits: Rect2 = Rect2()
@export var pc: Node2D

func _init() -> void:
	prompt_text = "Open"

## Flips visibility/processing between the two areas. Pure/static so it's unit-testable
## without a live scene tree.
static func toggle_areas(current_area_node: Node2D, target_area_node: Node2D) -> void:
	current_area_node.visible = false
	current_area_node.process_mode = Node.PROCESS_MODE_DISABLED
	target_area_node.visible = true
	target_area_node.process_mode = Node.PROCESS_MODE_INHERIT

func interact() -> void:
	toggle_areas(current_area, target_area)
	pc.global_position = entry_marker.global_position
	camera.limit_left = int(target_camera_limits.position.x)
	camera.limit_top = int(target_camera_limits.position.y)
	camera.limit_right = int(target_camera_limits.end.x)
	camera.limit_bottom = int(target_camera_limits.end.y)
	interacted.emit()
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_door_transition.gd
```
Expected: nine `ok ...` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/door.gd tests/test_door_transition.gd
git commit -m "feat(world): add Door (no-load-screen building transition)"
```

---

### Task 8: PCController + InteractPrompt

**Files:**
- Create: `world/pc_controller.gd`
- Create: `world/ui/interact_prompt.gd`
- Test: `tests/test_interact_prompt.gd`

**Interfaces:**
- Consumes: `Interactable.nearest()` (Task 6), the `move_up`/`move_down`/`move_left`/`move_right`
  Input Map actions (Task 1).
- Produces: `PCController` (`extends CharacterBody2D`) with `move_speed: float` and
  `nearest_interactable() -> Interactable`; `InteractPrompt` (`extends Label`) with
  `show_prompt(text: String) -> void` / `hide_prompt() -> void`. Task 11 (`town_demo.gd`) polls
  `nearest_interactable()` each frame to drive `InteractPrompt`, and calls `.interact()` on it when the
  `interact` action fires.
- Movement feel itself is **not** automated-tested (manual playtest, per the Global Constraints) — only
  `InteractPrompt`'s show/hide logic gets a headless test here.

- [ ] **Step 1: Write the failing test (InteractPrompt only)**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var prompt := InteractPrompt.new()
	_check(not prompt.visible, "InteractPrompt starts hidden")
	prompt.show_prompt("Talk")
	_check(prompt.visible, "show_prompt() makes it visible")
	_check(prompt.text == "Talk", "show_prompt() sets the label text")
	prompt.hide_prompt()
	_check(not prompt.visible, "hide_prompt() hides it again")
	prompt.free()  # a Label (Node, not RefCounted) never added to a tree — free explicitly
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_interact_prompt.gd
```
Expected: an identifier error — `InteractPrompt` does not exist yet.

- [ ] **Step 3: Write `InteractPrompt`**

```gdscript
class_name InteractPrompt
extends Label

## Tiny show/hide prompt bubble (spec §4) — shows whichever Interactable's prompt_text
## the PC's interaction reach currently has as its nearest candidate.

func _init() -> void:
	hide()

func show_prompt(prompt_text: String) -> void:
	text = prompt_text
	show()

func hide_prompt() -> void:
	hide()
```

- [ ] **Step 4: Write `PCController`** (no automated test — movement feel is a manual playtest call
  per the Global Constraints; this class is exercised for real in Task 11's manual verification)

```gdscript
class_name PCController
extends CharacterBody2D

## The player-controlled body: free-continuous movement (spec §2) + interaction-reach
## tracking (spec §4). Movement feel itself is a manual playtest call (CLAUDE.md §5 hard
## ceiling) — only Interactable.nearest() (tested in Task 6) backs the logic here.

@export var move_speed: float = 90.0

var _tracked: Array[Interactable] = []

func _ready() -> void:
	var reach := Area2D.new()
	reach.name = "InteractionReach"
	reach.monitoring = true
	reach.monitorable = false
	reach.collision_layer = 0
	reach.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	reach.add_child(shape)
	add_child(reach)
	reach.area_entered.connect(_on_reach_area_entered)
	reach.area_exited.connect(_on_reach_area_exited)

func _on_reach_area_entered(area: Area2D) -> void:
	if area is Interactable and not _tracked.has(area):
		_tracked.append(area as Interactable)

func _on_reach_area_exited(area: Area2D) -> void:
	if area is Interactable:
		_tracked.erase(area)

func nearest_interactable() -> Interactable:
	return Interactable.nearest(_tracked, global_position)

func _physics_process(_delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	velocity = input_vector.normalized() * move_speed
	move_and_slide()
```

- [ ] **Step 5: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 6: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_interact_prompt.gd
```
Expected: four `ok ...` lines, no `FAIL`.

- [ ] **Step 7: Commit**

```bash
git add world/pc_controller.gd world/ui/interact_prompt.gd tests/test_interact_prompt.gd
git commit -m "feat(world): add PCController (free-continuous movement + interaction reach) and InteractPrompt"
```

---

### Task 9: Villager

**Files:**
- Create: `world/villager.gd`
- Test: `tests/test_villager_wander.gd`

**Interfaces:**
- Consumes: `Interactable` (Task 6), `DialogueSet` (Task 2).
- Produces: `Villager` (`extends CharacterBody2D`) with `dialogue: DialogueSet`, `can_wander: bool`,
  `wander_leash_radius: float`, signal `dialogue_requested(dialogue_set: DialogueSet)`, and
  `static func wander_target(origin: Vector2, leash_radius: float, angle: float, distance_fraction: float) -> Vector2`.
  Task 11 (`town_demo.gd`) instantiates several `Villager`s (wandering) and one more with
  `can_wander = false` as the Shopkeeper, connecting `dialogue_requested` to `DialogueBox.open()`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# angle = 0 means "straight along +X"; distance_fraction = 1.0 means "at the full radius".
	var target_east: Vector2 = Villager.wander_target(Vector2(100, 100), 50.0, 0.0, 1.0)
	_check(target_east.is_equal_approx(Vector2(150, 100)), "wander_target at angle 0, full radius, lands due east")

	# distance_fraction = 0.0 always returns the origin regardless of angle.
	var target_origin: Vector2 = Villager.wander_target(Vector2(100, 100), 50.0, 1.234, 0.0)
	_check(target_origin.is_equal_approx(Vector2(100, 100)), "wander_target at distance_fraction 0 returns the origin")

	# distance_fraction is clamped to [0, 1] even if given an out-of-range value.
	var target_clamped: Vector2 = Villager.wander_target(Vector2(0, 0), 50.0, 0.0, 5.0)
	_check(target_clamped.is_equal_approx(Vector2(50, 0)), "wander_target clamps distance_fraction above 1.0")

	# Property-style check: for many random samples, the picked point never leaves the leash radius.
	var origin := Vector2(200, 200)
	var radius: float = 40.0
	var all_within_radius: bool = true
	for i in range(200):
		var angle: float = randf_range(0.0, TAU)
		var fraction: float = randf()
		var sample: Vector2 = Villager.wander_target(origin, radius, angle, fraction)
		if sample.distance_to(origin) > radius + 0.001:
			all_within_radius = false
			break
	_check(all_within_radius, "200 random wander_target samples all stay within the leash radius")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_villager_wander.gd
```
Expected: an identifier error — `Villager` does not exist yet.

- [ ] **Step 3: Write `Villager`**

```gdscript
class_name Villager
extends CharacterBody2D

## A wandering, talkable NPC (spec §5). Also used, with can_wander = false, as the
## Shopkeeper. Composes a plain Interactable child (rather than extending Interactable
## directly) since this node is already a CharacterBody2D — see world/interactable.gd's
## doc comment for why.

signal dialogue_requested(dialogue_set: DialogueSet)

@export var dialogue: DialogueSet
@export var can_wander: bool = true
@export var wander_leash_radius: float = 48.0
@export var wander_speed: float = 40.0
@export var wander_pause_seconds: float = 1.5

var _home_position: Vector2
var _wander_target: Vector2
var _pause_timer: float = 0.0

## Picks a point within leash_radius of origin, given an explicit angle and distance
## fraction (both supplied by the caller so this stays a pure, deterministic,
## unit-testable function — the caller is responsible for supplying randomness).
static func wander_target(origin: Vector2, leash_radius: float, angle: float, distance_fraction: float) -> Vector2:
	var clamped_fraction: float = clampf(distance_fraction, 0.0, 1.0)
	return origin + Vector2(cos(angle), sin(angle)) * leash_radius * clamped_fraction

func _ready() -> void:
	_home_position = global_position
	_wander_target = global_position

	var interaction_zone := Interactable.new()
	interaction_zone.name = "InteractionZone"
	interaction_zone.prompt_text = "Talk"
	add_child(interaction_zone)
	interaction_zone.interacted.connect(_on_interacted)

func _physics_process(delta: float) -> void:
	if not can_wander:
		return
	if global_position.distance_to(_wander_target) < 2.0:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_wander_target = wander_target(_home_position, wander_leash_radius, randf_range(0.0, TAU), randf())
			_pause_timer = wander_pause_seconds
		return
	var direction: Vector2 = global_position.direction_to(_wander_target)
	velocity = direction * wander_speed
	move_and_slide()

func _on_interacted() -> void:
	dialogue_requested.emit(dialogue)
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_villager_wander.gd
```
Expected: four `ok ...` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/villager.gd tests/test_villager_wander.gd
git commit -m "feat(world): add Villager (wandering NPC, doubles as the Shopkeeper)"
```

---

### Task 10: AdventuringBoard

**Files:**
- Create: `world/adventuring_board.gd`
- Test: `tests/test_adventuring_board.gd`

**Interfaces:**
- Consumes: `Interactable` (Task 6), `QuestBoardEntry` (Task 4).
- Produces: `AdventuringBoard` (`extends Interactable`) with `entries: Array[QuestBoardEntry]` and
  signal `board_opened(entries: Array[QuestBoardEntry])`. Task 11 (`town_demo.gd`) connects
  `board_opened` to `AdventuringBoardPanel.open_for()`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var board := AdventuringBoard.new()
	_check(board.prompt_text == "Check the board", "AdventuringBoard sets its own prompt_text")
	_check(board.entries.size() == 0, "entries defaults to an empty array")

	var entry := QuestBoardEntry.new()
	entry.title = "Clear the Cellar"
	var entries: Array[QuestBoardEntry] = [entry]
	board.entries = entries

	# GDScript lambdas capture outer locals BY VALUE — a plain `var received` reassigned
	# inside the lambda would never propagate out. Route it through a one-element array.
	var received_box: Array = [[]]
	board.board_opened.connect(func(opened_entries: Array[QuestBoardEntry]) -> void: received_box[0] = opened_entries)
	board.interact()
	var received: Array = received_box[0]
	_check(received.size() == 1 and received[0] == entry, "interact() emits board_opened with the current entries")
	board.free()  # an Area2D (Node, not RefCounted) never added to a tree — free explicitly
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_adventuring_board.gd
```
Expected: an identifier error — `AdventuringBoard` does not exist yet.

- [ ] **Step 3: Write `AdventuringBoard`**

```gdscript
class_name AdventuringBoard
extends Interactable

## The town's Adventuring Board landmark (spec §7). Every entry in the 2026-07-07 demo is
## a blank placeholder — interact() just hands the current entries to whoever's listening
## (town_demo.gd, which opens AdventuringBoardPanel).

signal board_opened(entries: Array[QuestBoardEntry])

@export var entries: Array[QuestBoardEntry] = []

func _init() -> void:
	prompt_text = "Check the board"

func interact() -> void:
	board_opened.emit(entries)
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_adventuring_board.gd
```
Expected: three `ok ...` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/adventuring_board.gd tests/test_adventuring_board.gd
git commit -m "feat(world): add AdventuringBoard landmark"
```

---

### Task 11: TownDemo scene assembly

This is the integration task — everything from Tasks 1–10 gets wired into one running scene. There is
**no automated test for this task**: per the Global Constraints, movement feel, plaza scale/readability,
whether the wandering NPCs read as natural, and YSort occlusion are manual playtest calls
(`CLAUDE.md` §5 hard ceiling). The deliverable is verified by actually running the scene (Step 4).

**Files:**
- Create: `world/town_demo.tscn`
- Create: `world/town_demo.gd`

**Interfaces:**
- Consumes every class from Tasks 1–10: `Villager`, `Door`, `AdventuringBoard`, `PCController`,
  `InteractPrompt`, `DialogueBox`, `AdventuringBoardPanel`, `DialogueLine`, `DialogueSet`,
  `QuestBoardEntry`.
- Produces: a runnable scene at `res://world/town_demo.tscn`.

- [ ] **Step 1: Create the (near-empty) scene file**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://world/town_demo.gd" id="1_town_demo"]

[node name="TownDemo" type="Node2D"]
script = ExtResource("1_town_demo")
```

- [ ] **Step 2: Write `world/town_demo.gd`**

```gdscript
extends Node2D

## Root scene for the first-playable-town demo (2026-07-07-demo-town-prototype-design.md).
## Builds the whole plaza + shop interior in code, matching this project's existing
## "build scene content in code, not the editor" convention (combat.gd/AbilityMenuPanel).
## No content commitment: NPC lines, quest rows, and layout are all disposable placeholders.
## What's locked is the movement/interaction/scene-architecture pattern (spec §0).

const EXTERIOR_BOUNDS := Rect2(0, 0, 640, 360)
const INTERIOR_BOUNDS := Rect2(0, 0, 320, 240)

var _exterior: Node2D
var _interior: Node2D
var _pc: PCController
var _camera: Camera2D
var _dialogue_box: DialogueBox
var _board_panel: AdventuringBoardPanel
var _interact_prompt: InteractPrompt
var _shop_entry_marker: Marker2D

func _ready() -> void:
	_build_exterior()
	_build_interior()
	_build_pc()
	_build_camera()
	_build_ui()
	_wire_doors()
	_interior.visible = false
	_interior.process_mode = Node.PROCESS_MODE_DISABLED

func _build_exterior() -> void:
	_exterior = Node2D.new()
	_exterior.name = "Exterior"
	add_child(_exterior)

	var ground := ColorRect.new()
	ground.color = Color(0.55, 0.62, 0.42)
	ground.position = EXTERIOR_BOUNDS.position
	ground.size = EXTERIOR_BOUNDS.size
	_exterior.add_child(ground)

	_exterior.add_child(_build_shop_facade())

	var villager_data: Array[Dictionary] = [
		{"pos": Vector2(100, 250), "line": "Lovely day in the plaza, isn't it?"},
		{"pos": Vector2(300, 300), "line": "Careful near the old well, stranger."},
		{"pos": Vector2(200, 110), "line": "Welcome to town! The shop's got good stock."},
	]
	for i in range(villager_data.size()):
		var villager := Villager.new()
		villager.name = "Villager%d" % i
		villager.global_position = villager_data[i]["pos"]
		villager.dialogue = _make_dialogue(villager_data[i]["line"])
		villager.dialogue_requested.connect(_on_dialogue_requested)
		_exterior.add_child(villager)

	var board := AdventuringBoard.new()
	board.name = "AdventuringBoard"
	board.global_position = Vector2(150, 150)
	board.entries = _make_quest_entries()
	board.board_opened.connect(_on_board_opened)
	_exterior.add_child(board)

func _build_shop_facade() -> Node2D:
	var facade := Node2D.new()
	facade.name = "ShopFacade"
	facade.position = Vector2(450, 80)

	var body := ColorRect.new()
	body.color = Color(0.72, 0.58, 0.38)
	body.position = Vector2(0, 40)
	body.size = Vector2(150, 100)
	facade.add_child(body)

	var roof := Polygon2D.new()
	roof.color = Color(0.42, 0.26, 0.18)
	roof.polygon = PackedVector2Array([Vector2(-10, 40), Vector2(75, -20), Vector2(160, 40)])
	facade.add_child(roof)

	var door_visual := ColorRect.new()
	door_visual.color = Color(0.18, 0.12, 0.08)
	door_visual.position = Vector2(65, 100)
	door_visual.size = Vector2(20, 40)
	facade.add_child(door_visual)

	return facade

func _build_interior() -> void:
	_interior = Node2D.new()
	_interior.name = "ShopInterior"
	add_child(_interior)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.5, 0.42, 0.32)
	floor_rect.position = INTERIOR_BOUNDS.position
	floor_rect.size = INTERIOR_BOUNDS.size
	_interior.add_child(floor_rect)

	var shopkeeper := Villager.new()
	shopkeeper.name = "Shopkeeper"
	shopkeeper.can_wander = false
	shopkeeper.global_position = Vector2(160, 100)
	shopkeeper.dialogue = _make_dialogue("Welcome! Nothing's actually for sale yet — just testing the shop layout.")
	shopkeeper.dialogue_requested.connect(_on_dialogue_requested)
	_interior.add_child(shopkeeper)

	_shop_entry_marker = Marker2D.new()
	_shop_entry_marker.name = "EntryMarker"
	_shop_entry_marker.position = Vector2(160, 180)
	_interior.add_child(_shop_entry_marker)

func _build_pc() -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	_pc.global_position = Vector2(320, 300)

	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 8.0
	capsule.height = 20.0
	shape.shape = capsule
	_pc.add_child(shape)

	var visual := ColorRect.new()
	visual.color = Color(0.85, 0.55, 0.25)
	visual.position = Vector2(-8, -12)
	visual.size = Vector2(16, 24)
	_pc.add_child(visual)

	add_child(_pc)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	_camera.limit_left = int(EXTERIOR_BOUNDS.position.x)
	_camera.limit_top = int(EXTERIOR_BOUNDS.position.y)
	_camera.limit_right = int(EXTERIOR_BOUNDS.end.x)
	_camera.limit_bottom = int(EXTERIOR_BOUNDS.end.y)
	_pc.add_child(_camera)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	_interact_prompt = InteractPrompt.new()
	_interact_prompt.position = Vector2(16, 16)
	ui.add_child(_interact_prompt)

	_dialogue_box = DialogueBox.new()
	_dialogue_box.position = Vector2(20, 700)
	_dialogue_box.custom_minimum_size = Vector2(600, 100)
	ui.add_child(_dialogue_box)

	_board_panel = AdventuringBoardPanel.new()
	_board_panel.position = Vector2(500, 150)
	ui.add_child(_board_panel)
	_board_panel.close()

func _wire_doors() -> void:
	var shop_door := Door.new()
	shop_door.name = "ShopDoor"
	shop_door.global_position = Vector2(515, 120)
	shop_door.current_area = _exterior
	shop_door.target_area = _interior
	shop_door.entry_marker = _shop_entry_marker
	shop_door.camera = _camera
	shop_door.target_camera_limits = INTERIOR_BOUNDS
	shop_door.pc = _pc
	_exterior.add_child(shop_door)

	var exit_marker := Marker2D.new()
	exit_marker.name = "ShopExitMarker"
	exit_marker.position = Vector2(525, 230)
	_exterior.add_child(exit_marker)

	var exit_door := Door.new()
	exit_door.name = "ExitDoor"
	exit_door.global_position = Vector2(160, 200)
	exit_door.current_area = _interior
	exit_door.target_area = _exterior
	exit_door.entry_marker = exit_marker
	exit_door.camera = _camera
	exit_door.target_camera_limits = EXTERIOR_BOUNDS
	exit_door.pc = _pc
	_interior.add_child(exit_door)

func _make_dialogue(line_text: String) -> DialogueSet:
	var greeting := DialogueLine.new()
	greeting.speaker_name = "Villager"
	greeting.text = line_text
	var farewell := DialogueLine.new()
	farewell.speaker_name = "Villager"
	farewell.text = "Safe travels!"
	var lines: Array[DialogueLine] = [greeting, farewell]
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	return dialogue_set

func _make_quest_entries() -> Array[QuestBoardEntry]:
	var raw: Array[Dictionary] = [
		{"title": "Clear the Cellar", "category": QuestBoardEntry.Category.CURRENT, "body": "Coming soon."},
		{"title": "Lost Cat", "category": QuestBoardEntry.Category.SIDE, "body": "Coming soon."},
		{"title": "How We Got Here", "category": QuestBoardEntry.Category.RECAP, "body": "Coming soon."},
	]
	var entries: Array[QuestBoardEntry] = []
	for data in raw:
		var entry := QuestBoardEntry.new()
		entry.title = data["title"]
		entry.category = data["category"]
		entry.body_text = data["body"]
		entries.append(entry)
	return entries

func _on_dialogue_requested(dialogue_set: DialogueSet) -> void:
	_dialogue_box.open(dialogue_set)

func _on_board_opened(entries: Array[QuestBoardEntry]) -> void:
	_board_panel.open_for(entries)

func _process(_delta: float) -> void:
	if _dialogue_box.is_open():
		_interact_prompt.hide_prompt()
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		_interact_prompt.show_prompt(target.prompt_text)
	else:
		_interact_prompt.hide_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _dialogue_box.is_open():
		_dialogue_box.advance()
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		target.interact()
```

- [ ] **Step 3: Refresh the class cache, then manually verify by running the scene**

```bash
"$GODOT" --headless --path . --editor --quit
"$GODOT" --path . res://world/town_demo.tscn
```

This launches a real (non-headless) game window running `town_demo.tscn` directly, without touching
`project.godot`'s `run/main_scene` (which stays `combat.tscn`). Manually verify:

- [ ] WASD/arrow keys move the PC smoothly in all directions (free-continuous, not tile-snapped).
- [ ] Walking near a Villager shows the "Talk" prompt; pressing **E** opens the dialogue box with the
      greeting line; pressing **E** again advances to "Safe travels!"; pressing **E** a third time
      closes the box.
- [ ] The three Villagers wander around their home points and pause between moves.
- [ ] Walking near the Adventuring Board shows "Check the board"; pressing **E** opens the panel with
      three grouped rows (Current/Side/Recap); clicking a row shows its "Coming soon." detail text.
- [ ] Walking into the shop's door instantly swaps to the interior (no loading indicator, no visible
      hitch) — the Shopkeeper is there with its own dialogue line.
- [ ] Walking into the interior's exit door instantly swaps back to the exterior, with the PC
      appearing just outside the shop's door.
- [ ] The PC visually passes behind the shop facade when walking above it and in front when walking
      below it (YSort depth read) — **if this looks wrong**, it means `Exterior`/`ShopInterior` need
      `y_sort_enabled = true` set explicitly; add `_exterior.y_sort_enabled = true` and
      `_interior.y_sort_enabled = true` in `_build_exterior()`/`_build_interior()` and re-run.

- [ ] **Step 4: Commit**

```bash
git add world/town_demo.tscn world/town_demo.gd
git commit -m "feat(world): assemble the first-playable-town demo scene"
```

---

### Task 12: Full automated suite sweep

**Files:** none (verification only).

- [ ] **Step 1: Run every new test file to confirm nothing regressed relative to its own last run**

```bash
GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
for f in test_dialogue_set test_dialogue_box test_quest_board_entry test_adventuring_board_panel \
         test_interactable test_door_transition test_interact_prompt test_villager_wander test_adventuring_board; do
  echo "--- $f ---"
  "$GODOT" --headless --path . --script "res://tests/${f}.gd" 2>&1 | grep -E "^(ok|FAIL)" || true
done
```

Expected: every printed line starts with `ok `, zero lines start with `FAIL `.

- [ ] **Step 2: Run the project's existing combat suite to confirm nothing outside `world/` broke**

Per `CLAUDE.md`'s documented sweep, spot-check a couple of existing combat tests still pass (this plan
never touches `combat/`, so this is a quick sanity check, not a full re-verification):

```bash
"$GODOT" --headless --path . --script res://tests/test_extra_ability_ultimate_conflict.gd
```
Expected: same `ok ...` output as before this plan started (no `FAIL` lines).

- [ ] **Step 3: Update `CLAUDE.md`'s status section**

Open `CLAUDE.md`, find the "Next (as of 2026-07-07)" paragraph added when the spec was written, and
replace its final sentence (the "Next action: write the implementation plan..." line) to reflect that
the demo town is now built and manually playtested. Use this replacement text:

```
**Built and manually playtested (see the checklist in
`docs/superpowers/plans/2026-07-07-demo-town-prototype.md` Task 11).** Next: decide what real content
(if any) graduates from this throwaway demo into the actual Starter Town, or move on to another
out-of-combat system from `docs/design-bible/`.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: mark the demo town prototype built and playtested"
```
