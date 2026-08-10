# Quest System Foundation (Data Model + Quest Log + Tracker) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Quest/QuestObjective data model, a QuestLibrary registry, the PartyInventory
additions that drive quest progress/tracking, a new Quest Log panel (`Q`), and a generalized
on-screen quest tracker — all reusable by the tutorial and popup work that follows in later plans.

**Architecture:** Two new data `Resource` types (`Quest`, `QuestObjective`) authored once in a
static `QuestLibrary` registry (mirrors `ShopLibrary`/`EnemyLibrary`). `PartyInventory` gains
generic per-objective progress tracking (`quest_progress`) and a tracked-quest list
(`tracked_quest_ids`), with `lost_cat`'s two objectives special-cased against its existing
`has_quest_item`/`has_completed_quest` state so its real accept/turn-in flow (driven through the
Adventuring Board, untouched by this plan) keeps working unmodified. A new `QuestLogPanel` and a
rewritten `QuestTrackerPanel` are pure views over that state, built the same code-only-
construction way as `AdventuringBoardPanel`/`EventLogPanel`.

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless `SceneTree` test scripts (existing
project convention — no test framework dependency).

## Global Constraints

- Engine: Godot 4.6.3-stable. Language: GDScript only, no C#.
- Static typing throughout (typed vars, typed function signatures).
- Follow existing naming conventions: `PascalCase` classes, `snake_case` files/signals.
- Every new panel is built via code construction (no `.tscn`), matching
  `AdventuringBoardPanel`/`EventLogPanel`/`ProfessionsMenuPanel`.
- Every headless test is a `extends SceneTree` script under `tests/`, using the existing
  `_check(condition, label)` / `push_error("FAIL: ...")` / `quit(_failures)` convention.
- Do not touch `_on_board_entry_selected()` or any other part of Lost Cat's existing
  accept/turn-in flow in `town_demo.gd` — it keeps working exactly as it does today.
- Run tests via:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  (the executable lives one directory above the repo:
  `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`). After adding a new
  `class_name`, refresh the class cache first:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`.

---

### Task 1: `Quest` and `QuestObjective` data resources

**Files:**
- Create: `world/resources/quest_objective.gd`
- Create: `world/resources/quest.gd`
- Test: `tests/test_quest_resources.gd`

**Interfaces:**
- Produces: `QuestObjective` (`id: StringName`, `display_text: String`) and `Quest`
  (`id: StringName`, `title: String`, `description: String`, `category: Quest.Category`
  enum `{CURRENT, SIDE, TUTORIAL}`, `objectives: Array[QuestObjective]`, `reward_amber: int`).
  Every later task in this plan and the two follow-up plans construct/read these fields by name.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_quest_resources.gd
extends SceneTree

## Headless test for the Quest/QuestObjective data resources (2026-08-10 quest-system-and-
## tutorial design §3) — pure data, so this just proves construction and field access work.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var obj := QuestObjective.new()
	obj.id = &"move"
	obj.display_text = "Move around using WASD."
	_check(obj.id == &"move", "QuestObjective.id round-trips")
	_check(obj.display_text == "Move around using WASD.", "QuestObjective.display_text round-trips")

	var quest := Quest.new()
	quest.id = &"tutorial"
	quest.title = "Getting Started"
	quest.description = "Learn the basics before you set out."
	quest.category = Quest.Category.TUTORIAL
	quest.objectives = [obj]
	quest.reward_amber = 25
	_check(quest.category == Quest.Category.TUTORIAL, "Quest.category round-trips")
	_check(quest.objectives.size() == 1, "Quest.objectives holds the appended QuestObjective (got %d)" % quest.objectives.size())
	_check(quest.objectives[0].id == &"move", "the stored objective is the same instance (id matches)")
	_check(quest.category != Quest.Category.CURRENT, "TUTORIAL is distinct from CURRENT")

	print(("QUEST RESOURCES TEST PASSED" if _failures == 0 else "QUEST RESOURCES TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_resources.gd`
Expected: FAIL — `QuestObjective`/`Quest` classes don't exist yet (parse/identifier error).

- [ ] **Step 3: Write the resource classes**

```gdscript
# world/resources/quest_objective.gd
class_name QuestObjective
extends Resource

## One step within a Quest's objectives array (2026-08-10 quest-system-and-tutorial design §3).
## Data only — completion is tracked externally by PartyInventory.is_objective_complete().

@export var id: StringName = &""
@export var display_text: String = ""
```

```gdscript
# world/resources/quest.gd
class_name Quest
extends Resource

## Quest data (2026-08-10 quest-system-and-tutorial design §3) — authored once per quest in
## QuestLibrary, read by QuestLogPanel/QuestTrackerPanel. Objectives are ordered; PartyInventory
## tracks per-quest completion against each QuestObjective's id.

enum Category { CURRENT, SIDE, TUTORIAL }

@export var id: StringName = &""
@export var title: String = ""
@export var description: String = ""
@export var category: Category = Category.SIDE
@export var objectives: Array[QuestObjective] = []
@export var reward_amber: int = 0   ## [ASSUMPTION] placeholder, not balanced (CLAUDE.md §4)
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_resources.gd`
Expected: PASS — every line prints `ok`, script exits 0.

- [ ] **Step 5: Commit**

```bash
git add world/resources/quest_objective.gd world/resources/quest.gd tests/test_quest_resources.gd
git commit -m "feat(quests): add Quest/QuestObjective data resources"
```

---

### Task 2: `QuestLibrary` registry

**Files:**
- Create: `world/quest_library.gd`
- Test: `tests/test_quest_library.gd`

**Interfaces:**
- Consumes: `Quest`, `QuestObjective` (Task 1).
- Produces: `QuestLibrary.get_quest(quest_id: StringName) -> Quest` (null if unknown) and
  `QuestLibrary.all_quests() -> Array[Quest]`. Later tasks/plans look up `&"lost_cat"` and
  `&"tutorial"` by these exact ids.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_quest_library.gd
extends SceneTree

## Headless test for QuestLibrary (2026-08-10 quest-system-and-tutorial design §3).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(QuestLibrary.get_quest(&"nonexistent") == null, "an unknown quest id returns null")

	var lost_cat: Quest = QuestLibrary.get_quest(&"lost_cat")
	_check(lost_cat != null, "lost_cat is registered")
	_check(lost_cat.objectives.size() == 2, "lost_cat has 2 objectives (got %d)" % lost_cat.objectives.size())
	_check(lost_cat.objectives[0].id == &"find_cat", "lost_cat's first objective is 'find_cat'")
	_check(lost_cat.objectives[1].id == &"return_cat", "lost_cat's second objective is 'return_cat'")
	_check(lost_cat.category == Quest.Category.SIDE, "lost_cat is category SIDE")

	var tutorial: Quest = QuestLibrary.get_quest(&"tutorial")
	_check(tutorial != null, "tutorial is registered")
	_check(tutorial.objectives.size() == 8, "tutorial has 8 objectives (got %d)" % tutorial.objectives.size())
	_check(tutorial.category == Quest.Category.TUTORIAL, "tutorial is category TUTORIAL")
	_check(tutorial.objectives[0].id == &"move", "tutorial's first objective is 'move'")
	_check(tutorial.objectives[7].id == &"win_fight", "tutorial's last objective is 'win_fight'")
	_check(tutorial.reward_amber > 0, "tutorial grants a placeholder Amber reward")

	var first_call: Quest = QuestLibrary.get_quest(&"lost_cat")
	var second_call: Quest = QuestLibrary.get_quest(&"lost_cat")
	_check(first_call != second_call, "each call returns a fresh instance, not a shared one (mirrors ShopLibrary's convention)")

	_check(QuestLibrary.all_quests().size() == 2, "all_quests() returns both authored quests")

	print(("QUEST LIBRARY TEST PASSED" if _failures == 0 else "QUEST LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_library.gd`
Expected: FAIL — `QuestLibrary` doesn't exist yet.

- [ ] **Step 3: Write the registry**

```gdscript
# world/quest_library.gd
class_name QuestLibrary
extends RefCounted

## Code registry of authored Quest data (2026-08-10 quest-system-and-tutorial design §3), mirrors
## ShopLibrary/EnemyLibrary's static-registry convention. Every call builds fresh Quest/
## QuestObjective instances so repeated lookups never share Resource instances across scenes.

static func get_quest(quest_id: StringName) -> Quest:
	for quest: Quest in all_quests():
		if quest.id == quest_id:
			return quest
	return null

static func all_quests() -> Array[Quest]:
	return [_lost_cat(), _tutorial()]

static func _objective(id: StringName, display_text: String) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = id
	o.display_text = display_text
	return o

## Re-authored for the Quest Log (2026-08-10 design §2) — the actual accept/turn-in mechanics
## still live in town_demo.gd's _on_board_entry_selected(), untouched by this plan. This is
## display data only; PartyInventory.is_objective_complete() special-cases these two ids against
## the existing has_quest_item(&"rescued_cat")/has_completed_quest(&"lost_cat") state.
static func _lost_cat() -> Quest:
	var q := Quest.new()
	q.id = &"lost_cat"
	q.title = "Lost Cat"
	q.description = "A cat's gone missing — last seen near the old dungeon entrance. Whoever finds it should bring it back to the Adventuring Board."
	q.category = Quest.Category.SIDE
	q.objectives = [
		_objective(&"find_cat", "Rescue the cat from the dungeon."),
		_objective(&"return_cat", "Bring Whiskers back to the Adventuring Board."),
	]
	return q

static func _tutorial() -> Quest:
	var q := Quest.new()
	q.id = &"tutorial"
	q.title = "Getting Started"
	q.description = "Learn the basics before you set out."
	q.category = Quest.Category.TUTORIAL
	q.objectives = [
		_objective(&"move", "Move around using WASD."),
		_objective(&"open_inventory", "Press I to open your Inventory."),
		_objective(&"equip_gear", "Equip a piece of gear."),
		_objective(&"open_event_log", "Press L to open the Event Log."),
		_objective(&"open_professions", "Press P to open your Professions."),
		_objective(&"open_legend", "Press K to open the Interactable Legend."),
		_objective(&"visit_shop", "Visit the General Store and speak with the Shopkeeper."),
		_objective(&"win_fight", "Win a fight against an overworld enemy."),
	]
	q.reward_amber = 25   ## [ASSUMPTION] placeholder, not balanced (CLAUDE.md §4)
	return q
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_library.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/quest_library.gd tests/test_quest_library.gd
git commit -m "feat(quests): add QuestLibrary with lost_cat and tutorial quest data"
```

---

### Task 3: `PartyInventory` quest-progress additions

**Files:**
- Modify: `economy/resources/party_inventory.gd`
- Modify: `tests/test_party_inventory_quest_state.gd`

**Interfaces:**
- Consumes: `Quest`, `QuestObjective`, `QuestLibrary.get_quest()` (Tasks 1-2).
- Produces: `quest_progress: Dictionary`, `tracked_quest_ids: Array[StringName]`,
  `complete_objective(quest_id, objective_id)`, `is_objective_complete(quest_id, objective_id) -> bool`,
  `next_incomplete_objective(quest_id) -> QuestObjective` (null if all complete or quest unknown),
  `is_quest_tracked(quest_id) -> bool`, `set_quest_tracked(quest_id, tracked: bool)`,
  `abandon_quest(quest_id)`. `accept_quest()` now also adds to `tracked_quest_ids` (existing
  behavior — appending to `accepted_quest_ids` once, no duplicates — is unchanged).

- [ ] **Step 1: Write the failing test**

Add to the end of `tests/test_party_inventory_quest_state.gd`, replacing its final two lines
(the `print(...)`/`quit(_failures)` pair) with the new checks followed by that same pair:

```gdscript
	_check(not inv.has_accepted_quest(&"some_other_quest"), "a different quest id is unaffected")

	# --- New in 2026-08-10 quest-system-and-tutorial design §3 ---

	var inv2 := PartyInventory.new()
	_check(inv2.quest_progress.is_empty(), "quest_progress starts empty")
	_check(inv2.tracked_quest_ids.is_empty(), "tracked_quest_ids starts empty")

	inv2.accept_quest(&"tutorial")
	_check(inv2.is_quest_tracked(&"tutorial"), "accepting a quest tracks it by default")

	_check(not inv2.is_objective_complete(&"tutorial", &"move"), "a fresh objective isn't complete")
	var first: QuestObjective = inv2.next_incomplete_objective(&"tutorial")
	_check(first.id == &"move", "next_incomplete_objective returns the first objective in order")

	inv2.complete_objective(&"tutorial", &"move")
	_check(inv2.is_objective_complete(&"tutorial", &"move"), "complete_objective marks it complete")
	var second: QuestObjective = inv2.next_incomplete_objective(&"tutorial")
	_check(second.id == &"open_inventory", "next_incomplete_objective advances once the prior one completes")

	inv2.complete_objective(&"tutorial", &"move")
	_check(inv2.quest_progress[&"tutorial"].size() == 1, "completing the same objective twice doesn't duplicate it (got %d)" % inv2.quest_progress[&"tutorial"].size())

	inv2.set_quest_tracked(&"tutorial", false)
	_check(not inv2.is_quest_tracked(&"tutorial"), "set_quest_tracked(false) untracks")
	_check(inv2.has_accepted_quest(&"tutorial"), "untracking doesn't abandon the quest")

	inv2.abandon_quest(&"tutorial")
	_check(not inv2.has_accepted_quest(&"tutorial"), "abandon_quest removes it from accepted_quest_ids")
	_check(not inv2.is_quest_tracked(&"tutorial"), "abandon_quest also untracks it")

	_check(inv2.next_incomplete_objective(&"nonexistent") == null, "an unknown quest id returns null, not a crash")

	# lost_cat's objectives are special-cased against its existing has_quest_item/has_completed_quest state.
	var inv3 := PartyInventory.new()
	inv3.accept_quest(&"lost_cat")
	_check(inv3.next_incomplete_objective(&"lost_cat").id == &"find_cat", "lost_cat starts on find_cat")
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	inv3.give_quest_item(cat)
	_check(inv3.is_objective_complete(&"lost_cat", &"find_cat"), "find_cat completes once the cat is held")
	_check(inv3.next_incomplete_objective(&"lost_cat").id == &"return_cat", "lost_cat advances to return_cat")
	inv3.consume_quest_item(&"rescued_cat")
	inv3.complete_quest(&"lost_cat")
	_check(inv3.is_objective_complete(&"lost_cat", &"return_cat"), "return_cat completes once the quest is turned in")
	_check(inv3.next_incomplete_objective(&"lost_cat") == null, "lost_cat has no incomplete objectives left")

	print(("PARTY INVENTORY QUEST STATE TEST PASSED" if _failures == 0 else "PARTY INVENTORY QUEST STATE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: FAIL — `quest_progress`/`tracked_quest_ids`/the new methods don't exist yet.

- [ ] **Step 3: Implement the additions**

In `economy/resources/party_inventory.gd`, add two new `@export` fields directly after the
existing `@export var completed_quest_ids: Array[StringName] = []` (currently line 28):

```gdscript
@export var quest_progress: Dictionary = {}       # StringName quest_id -> Array[StringName] completed objective ids
@export var tracked_quest_ids: Array[StringName] = []
```

Replace the existing `accept_quest()` method (currently lines 142-144):

```gdscript
func accept_quest(quest_id: StringName) -> void:
	if not accepted_quest_ids.has(quest_id):
		accepted_quest_ids.append(quest_id)
		tracked_quest_ids.append(quest_id)
```

Add the following new methods immediately after the existing `has_completed_quest()` method
(currently lines 153-154, right before `gain_jackpot()`):

```gdscript
## Marks one QuestObjective complete for a generic (non-lost_cat) quest. lost_cat's objectives
## are derived from its existing quest-item/completion state instead — see is_objective_complete().
func complete_objective(quest_id: StringName, objective_id: StringName) -> void:
	if not quest_progress.has(quest_id):
		quest_progress[quest_id] = []
	var completed: Array = quest_progress[quest_id]
	if not completed.has(objective_id):
		completed.append(objective_id)

## lost_cat is special-cased against state that already exists for other reasons (its Adventuring
## Board accept/turn-in flow, untouched by this plan) rather than requiring complete_objective()
## calls that flow doesn't make. Every other quest reads quest_progress directly.
func is_objective_complete(quest_id: StringName, objective_id: StringName) -> bool:
	if quest_id == &"lost_cat":
		if objective_id == &"find_cat":
			return has_quest_item(&"rescued_cat") or has_completed_quest(&"lost_cat")
		if objective_id == &"return_cat":
			return has_completed_quest(&"lost_cat")
		return false
	var completed: Array = quest_progress.get(quest_id, [])
	return completed.has(objective_id)

## The first objective (in Quest.objectives order) that isn't complete yet, or null once every
## objective is complete or [param quest_id] isn't registered in QuestLibrary.
func next_incomplete_objective(quest_id: StringName) -> QuestObjective:
	var quest: Quest = QuestLibrary.get_quest(quest_id)
	if quest == null:
		return null
	for objective: QuestObjective in quest.objectives:
		if not is_objective_complete(quest_id, objective.id):
			return objective
	return null

func is_quest_tracked(quest_id: StringName) -> bool:
	return tracked_quest_ids.has(quest_id)

## The Quest Log's Track checkbox (2026-08-10 design §4) — untracking hides a quest from the
## on-screen tracker without abandoning it.
func set_quest_tracked(quest_id: StringName, tracked: bool) -> void:
	if tracked and not tracked_quest_ids.has(quest_id):
		tracked_quest_ids.append(quest_id)
	elif not tracked:
		tracked_quest_ids.erase(quest_id)

func abandon_quest(quest_id: StringName) -> void:
	accepted_quest_ids.erase(quest_id)
	tracked_quest_ids.erase(quest_id)
	quest_progress.erase(quest_id)
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add economy/resources/party_inventory.gd tests/test_party_inventory_quest_state.gd
git commit -m "feat(quests): add generic per-objective progress tracking to PartyInventory"
```

---

### Task 4: `QuestLogPanel`

**Files:**
- Create: `world/ui/quest_log_panel.gd`
- Test: `tests/test_quest_log_panel.gd`

**Interfaces:**
- Consumes: `Quest`, `QuestObjective`, `QuestLibrary` (Tasks 1-2); `PartyInventory`'s
  `accepted_quest_ids`/`has_completed_quest()`/`is_objective_complete()`/`is_quest_tracked()`/
  `set_quest_tracked()`/`abandon_quest()` (Task 3).
- Produces: `QuestLogPanel.open_for(party_inventory: PartyInventory) -> void`, `close() -> void`,
  `is_open() -> bool` — same shape as `AdventuringBoardPanel`/`ProfessionsMenuPanel`, so later
  scene-wiring tasks in this plan (and this plan's Tasks 6-8) use it identically.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_quest_log_panel.gd
extends SceneTree

## Headless test for QuestLogPanel (2026-08-10 quest-system-and-tutorial design §4).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()
	inv.accept_quest(&"lost_cat")
	var panel := QuestLogPanel.new()

	panel.open_for(inv)
	_check(panel.is_open(), "opens")
	_check(panel.is_row_present_for_test(&"lost_cat"), "lost_cat shows as a row once accepted")

	panel.press_row_for_test(&"lost_cat")
	_check(panel.detail_text_for_test().contains("Rescue the cat"), "detail pane shows the first incomplete objective's text (got: %s)" % panel.detail_text_for_test())
	_check(not panel.detail_text_for_test().contains("[x]"), "no objective is checked off yet")

	panel.toggle_track_for_test(false)
	_check(not inv.is_quest_tracked(&"lost_cat"), "unticking Track untracks the quest")
	_check(inv.has_accepted_quest(&"lost_cat"), "untracking doesn't abandon the quest")

	panel.press_abandon_for_test()
	_check(not inv.has_accepted_quest(&"lost_cat"), "Abandon removes a SIDE quest from accepted_quest_ids")

	inv.accept_quest(&"tutorial")
	panel.open_for(inv)
	panel.press_row_for_test(&"tutorial")
	panel.press_abandon_for_test()
	_check(inv.has_accepted_quest(&"tutorial"), "Abandon has no effect on a TUTORIAL-category quest")

	panel.free()
	print(("QUEST LOG PANEL TEST PASSED" if _failures == 0 else "QUEST LOG PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_log_panel.gd`
Expected: FAIL — `QuestLogPanel` doesn't exist yet.

- [ ] **Step 3: Write the panel**

```gdscript
# world/ui/quest_log_panel.gd
class_name QuestLogPanel
extends Panel

## Quest Log window (2026-08-10 quest-system-and-tutorial design §4) — a Q-toggled panel listing
## every accepted quest (Active/Completed), with a detail pane showing the selected quest's
## description, objectives, and reward, a Track checkbox (the "untrack" ability), and an Abandon
## button disabled for TUTORIAL-category quests. Built the same code-only-construction way as
## AdventuringBoardPanel: every open_for() call rebuilds rows from scratch.

const PAD: float = 16.0
const ROW_H: float = 24.0
const LIST_W: float = 200.0
const PANEL_W: float = 560.0
const PANEL_H: float = 320.0
const DETAIL_X: float = PAD + LIST_W + PAD

var _party_inventory: PartyInventory
var _selected_quest_id: StringName = &""
var _row_buttons: Dictionary = {}   # StringName -> Button
var _detail_title: Label
var _detail_body: Label
var _track_checkbox: CheckBox
var _abandon_button: Button

func open_for(party_inventory: PartyInventory) -> void:
	_party_inventory = party_inventory
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	_rebuild()
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_row_buttons.clear()

	var active_ids: Array[StringName] = []
	var completed_ids: Array[StringName] = []
	for quest_id: StringName in _party_inventory.accepted_quest_ids:
		if _party_inventory.has_completed_quest(quest_id):
			completed_ids.append(quest_id)
		else:
			active_ids.append(quest_id)

	var y: float = PAD
	var active_header := Label.new()
	active_header.text = "Active"
	active_header.position = Vector2(PAD, y)
	add_child(active_header)
	y += ROW_H
	for quest_id: StringName in active_ids:
		y = _add_row(quest_id, y)

	var completed_header := Label.new()
	completed_header.text = "Completed"
	completed_header.position = Vector2(PAD, y)
	add_child(completed_header)
	y += ROW_H
	for quest_id: StringName in completed_ids:
		y = _add_row(quest_id, y)

	_build_detail_pane()
	if _selected_quest_id != &"" and (active_ids.has(_selected_quest_id) or completed_ids.has(_selected_quest_id)):
		_select_quest(_selected_quest_id)
	elif not active_ids.is_empty():
		_select_quest(active_ids[0])
	elif not completed_ids.is_empty():
		_select_quest(completed_ids[0])

func _add_row(quest_id: StringName, y: float) -> float:
	var quest: Quest = QuestLibrary.get_quest(quest_id)
	if quest == null:
		return y
	var btn := Button.new()
	btn.text = quest.title
	btn.position = Vector2(PAD, y)
	btn.custom_minimum_size = Vector2(LIST_W, ROW_H - 4.0)
	btn.pressed.connect(_select_quest.bind(quest_id))
	add_child(btn)
	_row_buttons[quest_id] = btn
	return y + ROW_H

func _build_detail_pane() -> void:
	_detail_title = Label.new()
	_detail_title.position = Vector2(DETAIL_X, PAD)
	_detail_title.custom_minimum_size = Vector2(PANEL_W - DETAIL_X - PAD, ROW_H)
	add_child(_detail_title)

	_detail_body = Label.new()
	_detail_body.position = Vector2(DETAIL_X, PAD + ROW_H + 4.0)
	_detail_body.custom_minimum_size = Vector2(PANEL_W - DETAIL_X - PAD, PANEL_H - PAD * 2.0 - ROW_H - 40.0)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_detail_body)

	_track_checkbox = CheckBox.new()
	_track_checkbox.text = "Track"
	_track_checkbox.position = Vector2(DETAIL_X, PANEL_H - PAD - ROW_H)
	_track_checkbox.toggled.connect(_on_track_toggled)
	add_child(_track_checkbox)

	_abandon_button = Button.new()
	_abandon_button.text = "Abandon"
	_abandon_button.position = Vector2(DETAIL_X + 100.0, PANEL_H - PAD - ROW_H)
	_abandon_button.custom_minimum_size = Vector2(90.0, ROW_H - 4.0)
	_abandon_button.pressed.connect(_on_abandon_pressed)
	add_child(_abandon_button)

func _select_quest(quest_id: StringName) -> void:
	_selected_quest_id = quest_id
	var quest: Quest = QuestLibrary.get_quest(quest_id)
	if quest == null:
		return
	_detail_title.text = quest.title
	var lines: Array[String] = [quest.description, ""]
	for objective: QuestObjective in quest.objectives:
		var mark: String = "[x]" if _party_inventory.is_objective_complete(quest_id, objective.id) else "[ ]"
		lines.append("%s %s" % [mark, objective.display_text])
	if quest.reward_amber > 0:
		lines.append("")
		lines.append("Reward: %d Amber" % quest.reward_amber)
	_detail_body.text = "\n".join(lines)

	_track_checkbox.set_pressed_no_signal(_party_inventory.is_quest_tracked(quest_id))
	var completed: bool = _party_inventory.has_completed_quest(quest_id)
	_abandon_button.disabled = completed or quest.category == Quest.Category.TUTORIAL
	_abandon_button.visible = not completed

func _on_track_toggled(pressed: bool) -> void:
	_party_inventory.set_quest_tracked(_selected_quest_id, pressed)

## Re-checks category itself rather than trusting only the Abandon button's `disabled` state —
## disabled blocks a real click, but this handler must be safe even if called directly.
func _on_abandon_pressed() -> void:
	var quest: Quest = QuestLibrary.get_quest(_selected_quest_id)
	if quest != null and quest.category == Quest.Category.TUTORIAL:
		return
	_party_inventory.abandon_quest(_selected_quest_id)
	_rebuild()

## --- Headless test hooks (mirrors AdventuringBoardPanel/EventLogPanel's convention) ---

func press_row_for_test(quest_id: StringName) -> void:
	_select_quest(quest_id)

func toggle_track_for_test(pressed: bool) -> void:
	_track_checkbox.button_pressed = pressed
	_on_track_toggled(pressed)

func press_abandon_for_test() -> void:
	_on_abandon_pressed()

func detail_text_for_test() -> String:
	return _detail_body.text

func is_row_present_for_test(quest_id: StringName) -> bool:
	return _row_buttons.has(quest_id)
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_log_panel.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/ui/quest_log_panel.gd tests/test_quest_log_panel.gd
git commit -m "feat(quests): add QuestLogPanel with Track/Abandon"
```

---

### Task 5: Generalize `QuestTrackerPanel`

**Files:**
- Modify: `world/ui/quest_tracker_panel.gd`
- Modify: `tests/test_quest_tracker_panel.gd`

**Interfaces:**
- Consumes: `Quest`, `QuestLibrary` (Tasks 1-2); `PartyInventory.tracked_quest_ids`/
  `has_completed_quest()`/`next_incomplete_objective()` (Task 3).
- Produces: `QuestTrackerPanel.refresh(party_inventory: PartyInventory) -> void` — same signature
  as today, so every existing call site (`town_demo.gd:666`, `overworld_demo.gd:703`,
  `dungeon_demo.gd:488`) keeps working with no changes. Also produces `text_for_test() -> String`
  (replaces the old bare `.text` property the previous `Label`-based version exposed).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_quest_tracker_panel.gd
extends SceneTree

## Headless test for QuestTrackerPanel (2026-08-10 quest-system-and-tutorial design §5) —
## rewritten from a single hardcoded-lost_cat Label into a generic multi-quest list.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()
	var tracker := QuestTrackerPanel.new()

	tracker.refresh(inv)
	_check(not tracker.visible, "hidden when nothing is tracked")

	inv.accept_quest(&"lost_cat")
	tracker.refresh(inv)
	_check(tracker.visible, "visible once a quest is accepted (accept_quest tracks by default)")
	_check(tracker.text_for_test().to_lower().contains("rescue"), "shows the rescue objective before holding the cat (got: %s)" % tracker.text_for_test())

	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	inv.give_quest_item(cat)
	tracker.refresh(inv)
	_check(tracker.text_for_test().to_lower().contains("bring"), "shows the bring-it-back objective once holding the cat")

	inv.accept_quest(&"tutorial")
	tracker.refresh(inv)
	_check(tracker.text_for_test().to_lower().contains("wasd"), "a second tracked quest also shows (got: %s)" % tracker.text_for_test())

	inv.set_quest_tracked(&"tutorial", false)
	tracker.refresh(inv)
	_check(not tracker.text_for_test().to_lower().contains("wasd"), "untracking a quest removes it from the tracker")

	inv.consume_quest_item(&"rescued_cat")
	inv.complete_quest(&"lost_cat")
	tracker.refresh(inv)
	_check(not tracker.visible, "hidden again once every tracked quest is either completed or untracked")

	tracker.free()
	print(("QUEST TRACKER PANEL TEST PASSED" if _failures == 0 else "QUEST TRACKER PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_tracker_panel.gd`
Expected: FAIL — `text_for_test()` doesn't exist on the current `Label`-based panel, and the
old single-`lost_cat` implementation doesn't handle a second tracked quest.

- [ ] **Step 3: Rewrite the panel**

Replace the entire contents of `world/ui/quest_tracker_panel.gd`:

```gdscript
class_name QuestTrackerPanel
extends VBoxContainer

## On-screen quest tracker (2026-08-10 quest-system-and-tutorial design §5) — one line-pair per
## tracked quest (PartyInventory.tracked_quest_ids), showing that quest's title and its next
## incomplete objective. Replaces the original single-hardcoded-lost_cat Label version (spec
## 2026-07-19 §3.5) now that PartyInventory.tracked_quest_ids/next_incomplete_objective() are
## generic. Hidden entirely when nothing is tracked (same as the original's behavior).

const MAX_DISPLAYED: int = 4

var _quest_labels: Array[Label] = []

func _init() -> void:
	for i in range(MAX_DISPLAYED):
		var lbl := Label.new()
		lbl.hide()
		add_child(lbl)
		_quest_labels.append(lbl)

func refresh(party_inventory: PartyInventory) -> void:
	var shown: int = 0
	for quest_id: StringName in party_inventory.tracked_quest_ids:
		if shown >= MAX_DISPLAYED:
			break
		if party_inventory.has_completed_quest(quest_id):
			continue
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		if quest == null:
			continue
		var objective: QuestObjective = party_inventory.next_incomplete_objective(quest_id)
		if objective == null:
			continue
		_quest_labels[shown].text = "%s\n%s" % [quest.title, objective.display_text]
		_quest_labels[shown].show()
		shown += 1
	for i in range(shown, MAX_DISPLAYED):
		_quest_labels[i].hide()
	visible = shown > 0

## --- Headless test hooks ---

func text_for_test() -> String:
	var lines: Array[String] = []
	for lbl: Label in _quest_labels:
		if lbl.visible:
			lines.append(lbl.text)
	return "\n".join(lines)
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_tracker_panel.gd`
Expected: PASS.

Also re-run the three existing scene-level regression suites to confirm `refresh()`'s unchanged
signature didn't break anything (`QuestTrackerPanel.new()` + `.refresh(_party_inventory)` call
sites are untouched, so these should already pass, but confirm):
- `tests/test_town_demo_talents.gd` (or any town_demo smoke test that exercises the UI layer)
- `tests/test_overworld_demo_professions.gd`
- `tests/test_dungeon_demo_professions.gd`

Expected: PASS on all three (no code in those scenes changed).

- [ ] **Step 5: Commit**

```bash
git add world/ui/quest_tracker_panel.gd tests/test_quest_tracker_panel.gd
git commit -m "feat(quests): generalize QuestTrackerPanel to show every tracked quest"
```

---

### Task 6: Wire `QuestLogPanel` into `town_demo.gd`

**Files:**
- Modify: `project.godot`
- Modify: `world/town_demo.gd`
- Test: `tests/test_town_demo_quest_log.gd`

**Interfaces:**
- Consumes: `QuestLogPanel` (Task 4), new input action `toggle_quest_log`.
- Produces: pressing `Q` in `town_demo.tscn` opens/closes the Quest Log; opening it is blocked
  while any other modal panel is open (same guard-chain convention already used for
  `_toggle_professions()`/inventory/stats), and every other panel's own open guard now also
  checks the Quest Log so nothing can open on top of it.

- [ ] **Step 1: Write the failing test**

Follows the existing scene-smoke-test convention (`tests/test_overworld_demo_professions.gd`):
instantiate the real `.tscn`, `await process_frame` twice so `_ready()` has actually built the
panels before touching them, then call the scene's own (underscore-prefixed but externally
callable) methods and fields directly — no wrapper hooks needed.

```gdscript
# tests/test_town_demo_quest_log.gd
extends SceneTree

## Headless smoke test: Quest Log opens/closes in town_demo.tscn and is mutually exclusive with
## the Professions panel (2026-08-10 quest-system-and-tutorial design §4). Mirrors
## tests/test_overworld_demo_professions.gd's instantiate/await-process_frame/direct-field-access
## convention.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(scene._quest_log_panel != null, "town_demo builds a QuestLogPanel")
	_check(not scene._quest_log_panel.is_open(), "Quest Log starts closed")

	scene._toggle_quest_log()
	_check(scene._quest_log_panel.is_open(), "_toggle_quest_log() opens the panel")
	_check(scene._pc.movement_paused_for_test(), "opening the Quest Log pauses PC movement")

	scene._toggle_quest_log()
	_check(not scene._quest_log_panel.is_open(), "_toggle_quest_log() again closes the panel")
	_check(not scene._pc.movement_paused_for_test(), "closing the Quest Log resumes PC movement")

	scene._toggle_quest_log()
	scene._toggle_professions()
	_check(scene._quest_log_panel.is_open(), "opening Professions while the Quest Log is open is blocked (Quest Log stays open)")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_quest_log.gd`
Expected: FAIL — `_quest_log_panel`/`_toggle_quest_log()` don't exist on `town_demo.gd` yet.

- [ ] **Step 3: Add the input action and wire the panel**

In `project.godot`, add a new action after the existing `toggle_professions` block (currently
ending at line 81):

```
toggle_quest_log={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

In `world/town_demo.gd`, add a new panel variable next to the existing `_professions_panel`
declaration (currently line 33):

```gdscript
var _quest_log_panel: QuestLogPanel
```

Construct it right after the existing Professions panel construction block (currently lines
360-363):

```gdscript
	_quest_log_panel = QuestLogPanel.new()
	_quest_log_panel.hide()
	_ui_layer.add_child(_quest_log_panel)
```

Add `_quest_log_panel.is_open()` to every "another panel is already open" guard chain that
currently checks `_professions_panel.is_open()` (currently lines 689, 702, 714, 726, 751) — e.g.
line 689 becomes:

```gdscript
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open() or _talent_panel.visible or _professions_panel.is_open() or _quest_log_panel.is_open():
```

(apply the same `or _quest_log_panel.is_open()` addition to lines 702, 714, and 726's guard, and
to line 751's `if _inventory_panel.visible or _talent_panel.visible or _professions_panel.is_open():`
guard).

Add the toggle handler right after the existing `_toggle_professions()` function (currently
lines 725-733), following its exact movement-pause convention:

```gdscript
## Quest Log (2026-08-10 quest-system-and-tutorial design §4) -- bound to 'Q'. Same toggle
## semantics as _toggle_inventory()/_toggle_stats()/_toggle_talents()/_toggle_professions().
func _toggle_quest_log() -> void:
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open() or _talent_panel.visible or _inventory_panel.visible or _professions_panel.is_open():
		return
	if _quest_log_panel.is_open():
		_quest_log_panel.close()
		_pc.set_movement_paused(false)
	else:
		_quest_log_panel.open_for(_party_inventory)
		_pc.set_movement_paused(true)
```

Add its input check right after the existing `toggle_professions` check in `_unhandled_input`
(currently lines 748-750):

```gdscript
	if event.is_action_pressed("toggle_quest_log"):
		_toggle_quest_log()
		return
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_quest_log.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.godot world/town_demo.gd tests/test_town_demo_quest_log.gd
git commit -m "feat(quests): wire the Quest Log panel into town_demo (Q)"
```

---

### Task 7: Wire `QuestLogPanel` into `overworld_demo.gd`

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_demo_quest_log.gd`

**Interfaces:** identical shape to Task 6, applied to `overworld_demo.gd`. The `toggle_quest_log`
input action already exists globally (added in Task 6's `project.godot` edit).

- [ ] **Step 1: Write the failing test**

Same convention as Task 6, mirroring `tests/test_overworld_demo_professions.gd` directly (same
scene, same instantiate/await-process_frame/direct-field-access pattern):

```gdscript
# tests/test_overworld_demo_quest_log.gd
extends SceneTree

## Headless smoke test: Quest Log opens/closes in overworld_demo.tscn (2026-08-10 quest-system-
## and-tutorial design §4), mirrors test_overworld_demo_professions.gd.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/overworld_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(scene._quest_log_panel != null, "overworld_demo builds a QuestLogPanel")
	_check(not scene._quest_log_panel.is_open(), "Quest Log starts closed")

	scene._toggle_quest_log()
	_check(scene._quest_log_panel.is_open(), "_toggle_quest_log() opens the panel")
	_check(scene._pc.movement_paused_for_test(), "opening the Quest Log pauses PC movement")

	scene._toggle_quest_log()
	_check(not scene._quest_log_panel.is_open(), "_toggle_quest_log() again closes the panel")
	_check(not scene._pc.movement_paused_for_test(), "closing the Quest Log resumes PC movement")

	scene._toggle_quest_log()
	scene._toggle_professions()
	_check(scene._quest_log_panel.is_open(), "opening Professions while the Quest Log is open is blocked")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_quest_log.gd`
Expected: FAIL — `_quest_log_panel`/`_toggle_quest_log()` don't exist on `overworld_demo.gd` yet.

- [ ] **Step 3: Wire the panel**

Add the panel variable next to `_professions_panel` (currently `overworld_demo.gd:58`):

```gdscript
var _quest_log_panel: QuestLogPanel
```

Construct it right after the existing Professions panel construction block (currently lines
291-294):

```gdscript
	_quest_log_panel = QuestLogPanel.new()
	_quest_log_panel.hide()
	ui.add_child(_quest_log_panel)
```

Add `or _quest_log_panel.is_open()` to every guard chain currently checking
`_professions_panel.is_open()` — this is six locations: `_toggle_inventory()`'s guard (currently
line 655), `_toggle_stats()`'s guard (line 668), `_toggle_talents()`'s guard (line 680),
`_toggle_professions()`'s own guard (line 692), the `_process()` interact-prompt-suppression
guard (line 705), and the post-toggle guard in `_unhandled_input()` (line 755).

Add the toggle handler right after the existing `_toggle_professions()` function (currently
lines 691-699), following its exact movement-pause convention:

```gdscript
## Quest Log (2026-08-10 quest-system-and-tutorial design §4) -- bound to 'Q'. Same toggle
## semantics as _toggle_inventory()/_toggle_stats()/_toggle_talents()/_toggle_professions().
func _toggle_quest_log() -> void:
	if _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible or _inventory_panel.visible or _professions_panel.is_open():
		return
	if _quest_log_panel.is_open():
		_quest_log_panel.close()
		_pc.set_movement_paused(false)
	else:
		_quest_log_panel.open_for(_party_inventory)
		_pc.set_movement_paused(true)
```

Add its input check right after the existing `toggle_professions` check in `_unhandled_input()`
(currently lines 752-754):

```gdscript
	if event.is_action_pressed("toggle_quest_log"):
		_toggle_quest_log()
		return
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_quest_log.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_quest_log.gd
git commit -m "feat(quests): wire the Quest Log panel into overworld_demo (Q)"
```

---

### Task 8: Wire `QuestLogPanel` into `dungeon_demo.gd`

**Files:**
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_dungeon_demo_quest_log.gd`

**Interfaces:** identical shape to Tasks 6-7, applied to `dungeon_demo.gd`.

- [ ] **Step 1: Write the failing test**

Same convention as Tasks 6-7, mirroring `tests/test_overworld_demo_professions.gd`'s
instantiate/await-process_frame/direct-field-access pattern for `dungeon_demo.tscn`:

```gdscript
# tests/test_dungeon_demo_quest_log.gd
extends SceneTree

## Headless smoke test: Quest Log opens/closes in dungeon_demo.tscn (2026-08-10 quest-system-and-
## tutorial design §4), mirrors test_overworld_demo_professions.gd.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/dungeon_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(scene._quest_log_panel != null, "dungeon_demo builds a QuestLogPanel")
	_check(not scene._quest_log_panel.is_open(), "Quest Log starts closed")

	scene._toggle_quest_log()
	_check(scene._quest_log_panel.is_open(), "_toggle_quest_log() opens the panel")
	_check(scene._pc.movement_paused_for_test(), "opening the Quest Log pauses PC movement")

	scene._toggle_quest_log()
	_check(not scene._quest_log_panel.is_open(), "_toggle_quest_log() again closes the panel")
	_check(not scene._pc.movement_paused_for_test(), "closing the Quest Log resumes PC movement")

	scene._toggle_quest_log()
	scene._toggle_professions()
	_check(scene._quest_log_panel.is_open(), "opening Professions while the Quest Log is open is blocked")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_quest_log.gd`
Expected: FAIL — `_quest_log_panel`/`_toggle_quest_log()` don't exist on `dungeon_demo.gd` yet.

- [ ] **Step 3: Wire the panel**

Add the panel variable next to `_professions_panel` (currently `dungeon_demo.gd:45`):

```gdscript
var _quest_log_panel: QuestLogPanel
```

Construct it right after the existing Professions panel construction block (currently lines
290-293):

```gdscript
	_quest_log_panel = QuestLogPanel.new()
	_quest_log_panel.hide()
	ui.add_child(_quest_log_panel)
```

Add `or _quest_log_panel.is_open()` to every guard chain currently checking
`_professions_panel.is_open()` (currently lines 490, 537, 546, 556, 568, 580 — the last of these,
580, is `_toggle_professions()`'s own guard).

Add the toggle handler right after the existing `_toggle_professions()` function (currently
lines 579-586), following its exact movement-pause convention:

```gdscript
## Quest Log (2026-08-10 quest-system-and-tutorial design §4) -- bound to 'Q'. Same toggle
## semantics as _toggle_inventory()/_toggle_stats()/_toggle_talents()/_toggle_professions().
func _toggle_quest_log() -> void:
	if _talent_panel.visible or _inventory_panel.visible or _professions_panel.is_open():
		return
	if _quest_log_panel.is_open():
		_quest_log_panel.close()
		_pc.set_movement_paused(false)
	else:
		_quest_log_panel.open_for(_party_inventory)
		_pc.set_movement_paused(true)
```

Add its input check right after the existing `toggle_professions` check in `_unhandled_input()`
(currently lines 534-536):

```gdscript
	if event.is_action_pressed("toggle_quest_log"):
		_toggle_quest_log()
		return
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_quest_log.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/dungeon_demo.gd tests/test_dungeon_demo_quest_log.gd
git commit -m "feat(quests): wire the Quest Log panel into dungeon_demo (Q)"
```

---

## After this plan

This delivers a working, testable Quest Log + tracker system with real content for both
`lost_cat` and the (not-yet-triggered) `tutorial` quest. Two follow-up plans remain, per the
spec's §14 split:

- **Plan 2:** `QuestPopupPanel` (NPC accept/turn-in), the tutorial's auto-start, wiring all 8
  tutorial objectives to their real triggers, and the Shopkeeper's tutorial-only dialogue line.
- **Plan 3:** `InteractableLegendPanel` (`K`), world hover tooltips (`WorldTooltip` +
  `Interactable.hover_description`) for the Old Well/Adventuring Board/Shop, and the "Respawn
  Gathering Nodes" debug button.
