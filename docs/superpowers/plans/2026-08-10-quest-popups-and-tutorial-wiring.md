# Quest Popups and Tutorial Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `QuestPopupPanel` (accept/turn-in UI) and retrofit Lost Cat's board flow to use
it; wire all 8 tutorial objectives to their real gameplay triggers; auto-start the tutorial quest
and auto-complete it once its objectives finish; give the Shopkeeper a tutorial-only dialogue line.

**Architecture:** `QuestPopupPanel` is a small code-constructed panel (mirrors `DialogueBox`) that
only emits signals (`accepted`/`declined`/`completed`) — the owning scene still performs the actual
`PartyInventory` mutation, matching `AdventuringBoardPanel`'s existing "emit and let the caller act"
convention. Every tutorial objective completes via a direct, unconditional
`PartyInventory.complete_objective(&"tutorial", &"<id>")` call at the real trigger's existing code
path — safe to call unconditionally (no "is this quest active" guard needed) because the tutorial
always auto-accepts before a player can reach any trigger, and `complete_objective()` is idempotent.
`PartyInventory.complete_objective()` itself now auto-calls `complete_quest()` once every objective
is done, and `complete_quest()` now grants the quest's `reward_amber` — both changes are additive
and a no-op for `lost_cat` (which never calls `complete_objective()`, and has `reward_amber == 0`).

**Scope note:** this plan pulls `InteractableLegendPanel` forward from what the design spec
(`docs/superpowers/specs/2026-08-10-quest-system-and-tutorial-design.md` §9) originally scoped as
"Plan 3" — the tutorial's "Open the Interactable Legend" objective needs that panel to exist, so it
can't wait. Plan 3 is left with just world hover tooltips (§10) and the Respawn Gathering Nodes
debug utility (§12), neither of which the tutorial depends on.

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless `SceneTree` test scripts.

## Global Constraints

- Engine: Godot 4.6.3-stable. Language: GDScript only, no C#. Static typing throughout.
- Follow existing naming conventions: `PascalCase` classes, `snake_case` files/signals.
- Every new panel is built via code construction (no `.tscn`), matching
  `AdventuringBoardPanel`/`DialogueBox`/`QuestLogPanel`.
- **Every new modal panel must set its own `.position` at construction time** — Plan 1's final
  review caught `QuestLogPanel` shipping unpositioned (rendered at (0,0) over the HUD); don't repeat
  that. `_talent_panel` sits at `Vector2(140, 60)`, `_board_panel` at `Vector2(500, 150)`.
- Every new modal panel must be added to (and itself check) every sibling modal panel's mutual-
  exclusion guard chain in each scene it's wired into — this project has repeatedly needed this
  fixed up after the fact; get it right the first time.
- Objective-completion calls (`complete_objective(&"tutorial", &"<id>")`) are unconditional, no
  "is the quest active" guard — safe because the tutorial always auto-accepts before any trigger is
  reachable (Task 8), and `complete_objective()`/`is_objective_complete()` are idempotent.
- Run tests via:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  (executable lives one directory above the repo:
  `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`). Refresh the class cache after
  adding a `class_name`: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`.
- Where a task says "find the guard chain by searching for `X`" — the exact current line number
  may have drifted since this plan was written; locate it by the surrounding function name or the
  literal string given, not by trusting the line number alone.

---

### Task 1: `PartyInventory` auto-completes a quest once its objectives finish, and grants its reward

**Files:**
- Modify: `economy/resources/party_inventory.gd`
- Modify: `tests/test_party_inventory_quest_state.gd`

**Interfaces:**
- Consumes: `Quest`, `QuestLibrary.get_quest()` (already exist), `PartyInventory.complete_objective()`/
  `next_incomplete_objective()`/`has_completed_quest()`/`complete_quest()` (already exist, from the
  quest-system-foundation plan).
- Produces: `complete_objective(quest_id, objective_id)` now auto-completes the quest once its last
  objective finishes. `complete_quest(quest_id)` now also grants `QuestLibrary.get_quest(quest_id).reward_amber`
  to `amber` (0 for quests with no authored reward, e.g. `lost_cat`). Every later task that calls
  `complete_objective()` for the tutorial relies on this to fire the reward automatically — no task
  after this one calls `complete_quest(&"tutorial")` directly.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_party_inventory_quest_state.gd`, replacing its final two lines (the
`print(...)`/`quit(_failures)` pair) with these new checks followed by that same pair:

```gdscript
	_check(inv3.next_incomplete_objective(&"lost_cat") == null, "lost_cat has no incomplete objectives left")

	# --- New: auto-complete + reward grant (quest-popups-and-tutorial-wiring plan, Task 1) ---

	var inv4 := PartyInventory.new()
	inv4.accept_quest(&"tutorial")
	var tutorial: Quest = QuestLibrary.get_quest(&"tutorial")
	for i in range(tutorial.objectives.size() - 1):
		inv4.complete_objective(&"tutorial", tutorial.objectives[i].id)
		_check(not inv4.has_completed_quest(&"tutorial"), "tutorial isn't auto-completed until the LAST objective finishes (got objective %d)" % i)
	var amber_before: int = inv4.amber
	inv4.complete_objective(&"tutorial", tutorial.objectives[tutorial.objectives.size() - 1].id)
	_check(inv4.has_completed_quest(&"tutorial"), "completing the last objective auto-completes the quest")
	_check(inv4.amber == amber_before + tutorial.reward_amber, "completing the quest grants its reward_amber (got %d, expected %d)" % [inv4.amber, amber_before + tutorial.reward_amber])

	# Completing an already-complete quest's objective again must not double-grant the reward.
	inv4.complete_objective(&"tutorial", tutorial.objectives[tutorial.objectives.size() - 1].id)
	_check(inv4.amber == amber_before + tutorial.reward_amber, "re-completing the last objective doesn't grant the reward twice (got %d)" % inv4.amber)

	# lost_cat never calls complete_objective(), so this change must be a no-op for its existing flow.
	var inv5 := PartyInventory.new()
	inv5.accept_quest(&"lost_cat")
	var lost_cat_amber_before: int = inv5.amber
	inv5.complete_quest(&"lost_cat")
	_check(inv5.amber == lost_cat_amber_before, "completing lost_cat grants 0 Amber (its reward_amber is 0 — it rewards via a QuestItem instead)")

	print(("PARTY INVENTORY QUEST STATE TEST PASSED" if _failures == 0 else "PARTY INVENTORY QUEST STATE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: FAIL — `complete_objective()` doesn't auto-complete yet, and `complete_quest()` doesn't
grant Amber yet, so the new checks fail.

- [ ] **Step 3: Implement the changes**

In `economy/resources/party_inventory.gd`, replace the existing `complete_objective()` method:

```gdscript
## Marks one QuestObjective complete for a generic (non-lost_cat) quest. Once every objective in
## the quest is complete, auto-completes the quest — deliberate design choice (2026-08-10
## quest-popups-and-tutorial-wiring plan Task 1): a fully objective-driven quest like the tutorial
## has no separate manual turn-in step, unlike lost_cat, which turns in at the board. lost_cat is
## unaffected since it never calls this method — see is_objective_complete()'s special-case.
func complete_objective(quest_id: StringName, objective_id: StringName) -> void:
	if not quest_progress.has(quest_id):
		quest_progress[quest_id] = []
	var completed: Array = quest_progress[quest_id]
	if not completed.has(objective_id):
		completed.append(objective_id)
	if next_incomplete_objective(quest_id) == null and not has_completed_quest(quest_id):
		complete_quest(quest_id)
```

Replace the existing `complete_quest()` method:

```gdscript
## Completing a quest also grants its authored reward_amber (0 for quests like lost_cat that
## reward via a QuestItem instead — see town_demo.gd's own turn-in handling). Guarded by the same
## "not already completed" check as before, so re-completing never double-grants.
func complete_quest(quest_id: StringName) -> void:
	if not completed_quest_ids.has(quest_id):
		completed_quest_ids.append(quest_id)
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		if quest != null:
			amber += quest.reward_amber
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add economy/resources/party_inventory.gd tests/test_party_inventory_quest_state.gd
git commit -m "feat(quests): auto-complete a quest once its objectives finish, grant its reward"
```

---

### Task 2: `QuestPopupPanel`

**Files:**
- Create: `world/ui/quest_popup_panel.gd`
- Test: `tests/test_quest_popup_panel.gd`

**Interfaces:**
- Consumes: `Quest`, `QuestObjective` (existing).
- Produces: `QuestPopupPanel.open_offer(quest: Quest) -> void`, `open_turn_in(quest: Quest) -> void`,
  `close() -> void`, `is_open() -> bool`, signals `accepted(quest_id: StringName)`, `declined`,
  `completed(quest_id: StringName)`. Task 3 wires these signals; nothing in this panel touches
  `PartyInventory` directly.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_quest_popup_panel.gd
extends SceneTree

## Headless test for QuestPopupPanel (2026-08-10 quest-popups-and-tutorial-wiring plan Task 2) — a
## small Offer/Turn-in popup, built the same code-only-construction way as DialogueBox. It only
## emits signals (mirrors AdventuringBoardPanel's "emit and let the caller act" convention); it
## never touches PartyInventory itself.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var quest: Quest = QuestLibrary.get_quest(&"lost_cat")
	var popup := QuestPopupPanel.new()
	_check(not popup.is_open(), "starts closed")

	var accepted_id_box: Array = [&""]
	popup.accepted.connect(func(id: StringName) -> void: accepted_id_box[0] = id)
	popup.open_offer(quest)
	_check(popup.is_open(), "open_offer() opens the panel")
	_check(popup.mode_for_test() == &"offer", "open_offer() sets offer mode")
	_check(popup.body_text_for_test().contains("A cat"), "the body text shows the quest description (got: %s)" % popup.body_text_for_test())
	popup.press_primary_for_test()
	_check(not popup.is_open(), "pressing the primary button (Accept) closes the panel")
	_check(accepted_id_box[0] == &"lost_cat", "pressing Accept emits accepted with the quest's id")

	var declined_box: Array = [false]
	popup.declined.connect(func() -> void: declined_box[0] = true)
	popup.open_offer(quest)
	popup.press_secondary_for_test()
	_check(not popup.is_open(), "pressing the secondary button (Decline) closes the panel")
	_check(declined_box[0], "pressing Decline emits declined")

	var completed_id_box: Array = [&""]
	popup.completed.connect(func(id: StringName) -> void: completed_id_box[0] = id)
	popup.open_turn_in(quest)
	_check(popup.mode_for_test() == &"turn_in", "open_turn_in() sets turn_in mode")
	popup.press_primary_for_test()
	_check(completed_id_box[0] == &"lost_cat", "pressing the primary button (Complete) in turn_in mode emits completed with the quest's id")

	var reward_quest: Quest = QuestLibrary.get_quest(&"tutorial")
	popup.open_turn_in(reward_quest)
	_check(popup.body_text_for_test().contains("Amber"), "a quest with a nonzero reward_amber shows a reward line (got: %s)" % popup.body_text_for_test())

	popup.free()
	print(("QUEST POPUP PANEL TEST PASSED" if _failures == 0 else "QUEST POPUP PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_popup_panel.gd`
Expected: FAIL — `QuestPopupPanel` doesn't exist yet.

- [ ] **Step 3: Write the panel**

```gdscript
# world/ui/quest_popup_panel.gd
class_name QuestPopupPanel
extends Panel

## NPC/board accept and turn-in popup (2026-08-10 quest-system-and-tutorial design §6). Built the
## same code-only-construction way as DialogueBox, since DialogueBox itself is strictly linear (no
## buttons). Pure emitter — never touches PartyInventory itself, mirroring AdventuringBoardPanel's
## "emit and let the caller act" convention (see its own party_selection_pressed doc comment).

signal accepted(quest_id: StringName)
signal declined
signal completed(quest_id: StringName)

const PANEL_W: float = 440.0
const PANEL_H: float = 200.0

var _mode: StringName = &""   # &"offer" or &"turn_in"
var _quest_id: StringName = &""
var _title_label: Label
var _body_label: Label
var _primary_button: Button    # Accept (offer) / Complete (turn_in)
var _secondary_button: Button  # Decline (offer only)

func _init() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size

	_title_label = Label.new()
	_title_label.position = Vector2(16, 8)
	add_child(_title_label)

	_body_label = Label.new()
	_body_label.position = Vector2(16, 32)
	_body_label.custom_minimum_size = Vector2(PANEL_W - 32.0, PANEL_H - 90.0)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_body_label)

	_primary_button = Button.new()
	_primary_button.position = Vector2(16, PANEL_H - 40.0)
	_primary_button.custom_minimum_size = Vector2(120.0, 28.0)
	_primary_button.pressed.connect(_on_primary_pressed)
	add_child(_primary_button)

	_secondary_button = Button.new()
	_secondary_button.position = Vector2(150.0, PANEL_H - 40.0)
	_secondary_button.custom_minimum_size = Vector2(120.0, 28.0)
	_secondary_button.pressed.connect(_on_secondary_pressed)
	add_child(_secondary_button)

	hide()

func open_offer(quest: Quest) -> void:
	_mode = &"offer"
	_quest_id = quest.id
	_title_label.text = quest.title
	var lines: Array[String] = [quest.description, ""]
	for objective: QuestObjective in quest.objectives:
		lines.append("- %s" % objective.display_text)
	_body_label.text = "\n".join(lines)
	_primary_button.text = "Accept"
	_secondary_button.visible = true
	_secondary_button.text = "Decline"
	show()

func open_turn_in(quest: Quest) -> void:
	_mode = &"turn_in"
	_quest_id = quest.id
	_title_label.text = quest.title
	var lines: Array[String] = [quest.description]
	if quest.reward_amber > 0:
		lines.append("")
		lines.append("Reward: %d Amber" % quest.reward_amber)
	_body_label.text = "\n".join(lines)
	_primary_button.text = "Complete"
	_secondary_button.visible = false
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _on_primary_pressed() -> void:
	var id: StringName = _quest_id
	var mode: StringName = _mode
	close()
	if mode == &"offer":
		accepted.emit(id)
	else:
		completed.emit(id)

func _on_secondary_pressed() -> void:
	close()
	declined.emit()

## --- Headless test hooks ---

func press_primary_for_test() -> void:
	_on_primary_pressed()

func press_secondary_for_test() -> void:
	_on_secondary_pressed()

func body_text_for_test() -> String:
	return _body_label.text

func mode_for_test() -> StringName:
	return _mode
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_popup_panel.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/ui/quest_popup_panel.gd tests/test_quest_popup_panel.gd
git commit -m "feat(quests): add QuestPopupPanel (accept/turn-in)"
```

---

### Task 3: Retrofit Lost Cat's board flow onto `QuestPopupPanel`

**Files:**
- Modify: `world/town_demo.gd`
- Modify: `tests/test_lost_cat_board_flow.gd`
- Modify: `tests/test_lost_cat_quest_full_sequence.gd`

**Interfaces:**
- Consumes: `QuestPopupPanel` (Task 2), `QuestLibrary.get_quest()` (existing).
- Produces: clicking an unaccepted board row now opens an Offer popup instead of accepting
  instantly; clicking a ready-to-turn-in row opens a Turn-in popup instead of completing instantly.
  Only pressing the popup's primary button actually mutates `PartyInventory`. This is a behavior
  change to two existing, already-shipped tests — both are updated in this task, not left broken.

- [ ] **Step 1: Update the two existing tests to expect the popup-mediated flow**

In `tests/test_lost_cat_board_flow.gd`, replace this block (currently around lines 36-38):

```gdscript
	# Click it: accepts.
	town._on_board_entry_selected(lost_cat)
	_check(inv.has_accepted_quest(&"lost_cat"), "clicking the unaccepted row accepts it")
```

with:

```gdscript
	# Click it: opens the accept popup instead of accepting directly.
	town._on_board_entry_selected(lost_cat)
	_check(town._quest_popup_panel.is_open(), "clicking the unaccepted row opens the accept popup")
	_check(town._quest_popup_panel.mode_for_test() == &"offer", "the popup opens in offer mode")
	town._quest_popup_panel.press_primary_for_test()
	_check(inv.has_accepted_quest(&"lost_cat"), "pressing Accept on the popup accepts the quest")
```

Replace this block (currently around lines 51-59):

```gdscript
	# Now the player holds the rescued cat — click again: turns in.
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	cat.display_name = "Whiskers, Rescued"
	inv.give_quest_item(cat)
	town._on_board_entry_selected(lost_cat)
	_check(not inv.has_quest_item(&"rescued_cat"), "turning in consumes the rescued_cat item")
	_check(inv.has_completed_quest(&"lost_cat"), "turning in completes the quest")
	_check(inv.has_quest_item(&"thank_you_note"), "turning in grants the Thank You Note")
```

with:

```gdscript
	# Now the player holds the rescued cat — click again: opens the turn-in popup.
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	cat.display_name = "Whiskers, Rescued"
	inv.give_quest_item(cat)
	town._on_board_entry_selected(lost_cat)
	_check(town._quest_popup_panel.is_open(), "clicking the ready-to-turn-in row opens the turn-in popup")
	_check(town._quest_popup_panel.mode_for_test() == &"turn_in", "the popup opens in turn_in mode")
	town._quest_popup_panel.press_primary_for_test()
	_check(not inv.has_quest_item(&"rescued_cat"), "pressing Complete on the popup consumes the rescued_cat item")
	_check(inv.has_completed_quest(&"lost_cat"), "pressing Complete on the popup completes the quest")
	_check(inv.has_quest_item(&"thank_you_note"), "pressing Complete on the popup grants the Thank You Note")
```

The other two no-op click checks in this file (accepted-but-not-ready, already-completed) are
untouched — those paths still never open a popup.

In `tests/test_lost_cat_quest_full_sequence.gd`, replace this block (currently around lines 34-35):

```gdscript
	_town._on_board_entry_selected(lost_cat)
	_check(inv.has_accepted_quest(&"lost_cat"), "accepted for real via the board handler")
```

with:

```gdscript
	_town._on_board_entry_selected(lost_cat)
	_town._quest_popup_panel.press_primary_for_test()
	_check(inv.has_accepted_quest(&"lost_cat"), "accepted for real via the board handler + popup")
```

Replace this block (currently around lines 67-69):

```gdscript
	_town._on_board_entry_selected(lost_cat)
	_check(inv.has_completed_quest(&"lost_cat"), "turned in for real via the board handler")
	_check(inv.has_quest_item(&"thank_you_note"), "the Thank You Note is granted")
```

with:

```gdscript
	_town._on_board_entry_selected(lost_cat)
	_town._quest_popup_panel.press_primary_for_test()
	_check(inv.has_completed_quest(&"lost_cat"), "turned in for real via the board handler + popup")
	_check(inv.has_quest_item(&"thank_you_note"), "the Thank You Note is granted")
```

- [ ] **Step 2: Run both tests to verify they fail**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_board_flow.gd`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_quest_full_sequence.gd`
Expected: FAIL on both — `_quest_popup_panel` doesn't exist on `town_demo.gd` yet, and
`_on_board_entry_selected` still mutates state directly instead of opening a popup.

- [ ] **Step 3: Wire the panel and retrofit the handler**

Add a new panel variable next to the existing `_quest_log_panel` declaration:

```gdscript
var _quest_popup_panel: QuestPopupPanel
```

Construct it right after the existing `_quest_log_panel` construction block (currently around
line 366 — search for `_quest_log_panel = QuestLogPanel.new()`), positioned so it doesn't sit on
top of the Adventuring Board panel (`Vector2(500, 150)`) or the Quest Log/Talent panel
(`Vector2(140, 60)`):

```gdscript
	_quest_popup_panel = QuestPopupPanel.new()
	_quest_popup_panel.position = Vector2(580, 350)
	_quest_popup_panel.hide()
	_ui_layer.add_child(_quest_popup_panel)
	_quest_popup_panel.accepted.connect(_on_quest_popup_accepted)
	_quest_popup_panel.completed.connect(_on_quest_popup_completed)
```

Replace the existing `_on_board_entry_selected()` function (currently at line 644):

```gdscript
## Lost Cat quest board interactivity (2026-07-19-lost-cat-quest-system-design.md §3.3, retrofitted
## onto QuestPopupPanel 2026-08-10): a placeholder row (empty id) always no-ops; an unaccepted row
## opens the Accept popup; an accepted-but-not-ready row no-ops; a completed row no-ops; the
## Lost Cat row specifically opens the Complete (turn-in) popup once the party holds the rescued
## cat. The actual accept_quest()/complete_quest() calls now live in
## _on_quest_popup_accepted()/_on_quest_popup_completed(), triggered by the popup's own buttons.
func _on_board_entry_selected(entry: QuestBoardEntry) -> void:
	if entry.id == &"":
		return
	if not _party_inventory.has_accepted_quest(entry.id):
		var quest: Quest = QuestLibrary.get_quest(entry.id)
		if quest == null:
			return
		_quest_popup_panel.open_offer(quest)
		return
	if _party_inventory.has_completed_quest(entry.id):
		return
	if entry.id == &"lost_cat" and _party_inventory.has_quest_item(&"rescued_cat"):
		var turn_in_quest: Quest = QuestLibrary.get_quest(entry.id)
		if turn_in_quest == null:
			return
		_quest_popup_panel.open_turn_in(turn_in_quest)
```

Add the two new signal handlers right after it:

```gdscript
func _on_quest_popup_accepted(quest_id: StringName) -> void:
	_party_inventory.accept_quest(quest_id)
	_board_panel.open_for(_make_quest_entries())

## lost_cat is the only quest turned in through this popup today; its specific item-consumption/
## reward-granting logic stays here (rather than generic in QuestPopupPanel) since it's unique to
## this one quest's board-driven flow.
func _on_quest_popup_completed(quest_id: StringName) -> void:
	if quest_id == &"lost_cat":
		_party_inventory.consume_quest_item(&"rescued_cat")
		_party_inventory.complete_quest(&"lost_cat")
		_party_inventory.give_quest_item(_make_thank_you_note())
	_board_panel.open_for(_make_quest_entries())
```

- [ ] **Step 4: Refresh the class cache, then run both tests to verify they pass**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_board_flow.gd`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_quest_full_sequence.gd`
Expected: PASS on both.

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd tests/test_lost_cat_board_flow.gd tests/test_lost_cat_quest_full_sequence.gd
git commit -m "feat(quests): retrofit Lost Cat's board accept/turn-in onto QuestPopupPanel"
```

---

### Task 4: `InteractableLegendPanel`

**Files:**
- Create: `world/ui/interactable_legend_panel.gd`
- Test: `tests/test_interactable_legend_panel.gd`

**Interfaces:**
- Produces: `InteractableLegendPanel.open() -> void`, `close() -> void`, `is_open() -> bool`. Static
  content, no external data dependency. Tasks 5-7 wire this into each scene.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_interactable_legend_panel.gd
extends SceneTree

## Headless test for InteractableLegendPanel (2026-08-10 quest-system-and-tutorial design §9,
## pulled forward into the quest-popups-and-tutorial-wiring plan's Task 4).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel := InteractableLegendPanel.new()
	_check(not panel.is_open(), "starts closed")
	_check(panel.row_count_for_test() == 6, "has all 6 interactable-type rows (got %d)" % panel.row_count_for_test())
	_check(panel.row_text_for_test(0).contains("Foraging"), "row 0 is Foraging")
	_check(panel.row_text_for_test(2).contains("Enemy"), "row 2 is Enemy")
	_check(panel.row_text_for_test(5).contains("Reward pickup"), "row 5 is Reward pickup")

	panel.open()
	_check(panel.is_open(), "open() opens the panel")
	panel.close()
	_check(not panel.is_open(), "close() closes the panel")

	panel.free()
	print(("INTERACTABLE LEGEND PANEL TEST PASSED" if _failures == 0 else "INTERACTABLE LEGEND PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_interactable_legend_panel.gd`
Expected: FAIL — `InteractableLegendPanel` doesn't exist yet.

- [ ] **Step 3: Write the panel**

```gdscript
# world/ui/interactable_legend_panel.gd
class_name InteractableLegendPanel
extends Panel

## Static reference glossary of overworld interactable types (2026-08-10 quest-system-and-tutorial
## design §9, pulled forward into the quest-popups-and-tutorial-wiring plan since the tutorial's
## "Open the Interactable Legend" objective needs this panel to exist). Matches the real
## placeholder visuals already used by GatheringNode/FishingSpot/OverworldEnemy/
## RandomEncounterNode/GroundItemPickup/RewardPickup — no new art.

const ROW_H: float = 24.0
const PAD: float = 16.0
const SWATCH_SIZE: float = 16.0

const ROWS: Array = [
	[Color(0.3, 0.7, 0.3), "Foraging node — Gather"],
	[Color(0.2, 0.4, 0.8), "Fishing spot — Fish"],
	[Color(0.7, 0.2, 0.2), "Enemy — Fight"],
	[Color(1.0, 0.85, 0.2), "Random Encounter — Investigate"],
	[Color(0.6, 0.6, 0.6), "Item pickup — Pick up"],
	[Color(0.9, 0.75, 0.15), "Reward pickup — Pick up (quest/dungeon reward)"],
]

func _init() -> void:
	var title := Label.new()
	title.text = "Interactable Legend"
	title.position = Vector2(PAD, PAD)
	add_child(title)

	var y: float = PAD + ROW_H
	for row: Array in ROWS:
		var swatch := ColorRect.new()
		swatch.color = row[0]
		swatch.position = Vector2(PAD, y + 2.0)
		swatch.size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		add_child(swatch)

		var label := Label.new()
		label.text = row[1]
		label.position = Vector2(PAD + SWATCH_SIZE + 8.0, y)
		add_child(label)

		y += ROW_H

	custom_minimum_size = Vector2(360.0, y + PAD)
	size = custom_minimum_size
	hide()

func open() -> void:
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

## --- Headless test hooks ---

func row_count_for_test() -> int:
	return ROWS.size()

func row_text_for_test(index: int) -> String:
	return ROWS[index][1]
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_interactable_legend_panel.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/ui/interactable_legend_panel.gd tests/test_interactable_legend_panel.gd
git commit -m "feat(quests): add InteractableLegendPanel"
```

---

### Task 5: Wire `InteractableLegendPanel` + the `open_legend` tutorial objective into `town_demo.gd`

**Files:**
- Modify: `project.godot`
- Modify: `world/town_demo.gd`
- Test: `tests/test_town_demo_legend.gd`

**Interfaces:**
- Consumes: `InteractableLegendPanel` (Task 4), new input action `toggle_interactable_legend`.
- Produces: pressing `K` in `town_demo.tscn` opens/closes the Legend; opening it completes the
  tutorial's `open_legend` objective; it's mutually exclusive with every other modal panel
  (Inventory/Stats/Talents/Professions/Quest Log), and — critically — every one of THOSE panels'
  own guard chains must now also block on the Legend being open (this is the same "retroactively
  update every sibling's guard" step Plan 1 had to do for Quest Log; do it correctly the first time
  here rather than needing a follow-up fix).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_town_demo_legend.gd
extends SceneTree

## Headless smoke test: Interactable Legend opens/closes in town_demo.tscn, completes the
## tutorial's open_legend objective, and is mutually exclusive with Professions (2026-08-10
## quest-popups-and-tutorial-wiring plan Task 5). Mirrors test_town_demo_quest_log.gd's convention.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	inv.accept_quest(&"tutorial")

	_check(scene._legend_panel != null, "town_demo builds an InteractableLegendPanel")
	_check(not scene._legend_panel.is_open(), "Legend starts closed")

	scene._toggle_legend()
	_check(scene._legend_panel.is_open(), "_toggle_legend() opens the panel")
	_check(inv.is_objective_complete(&"tutorial", &"open_legend"), "opening the Legend completes the tutorial's open_legend objective")

	scene._toggle_legend()
	_check(not scene._legend_panel.is_open(), "_toggle_legend() again closes the panel")

	scene._toggle_legend()
	scene._toggle_professions()
	_check(scene._legend_panel.is_open(), "opening Professions while the Legend is open is blocked (Legend stays open)")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	scene._toggle_legend()
	scene._toggle_quest_log()
	_check(not scene._quest_log_panel.is_open(), "opening the Quest Log while the Legend is open is blocked")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_legend.gd`
Expected: FAIL — `_legend_panel`/`_toggle_legend()` don't exist yet.

- [ ] **Step 3: Add the input action and wire the panel**

In `project.godot`, add a new action after the existing `toggle_quest_log` block:

```
toggle_interactable_legend={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":75,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

In `world/town_demo.gd`, add a new panel variable next to `_quest_log_panel`:

```gdscript
var _legend_panel: InteractableLegendPanel
```

Construct it right after the `_quest_popup_panel` construction block from Task 3:

```gdscript
	_legend_panel = InteractableLegendPanel.new()
	_legend_panel.position = Vector2(140, 60)
	_legend_panel.hide()
	_ui_layer.add_child(_legend_panel)
```

Add `or _legend_panel.is_open()` to every guard chain that currently checks
`_quest_log_panel.is_open()` — search for that exact string; it appears in `_toggle_inventory()`,
`_toggle_stats()`, `_toggle_talents()`, `_toggle_professions()`, `_toggle_quest_log()`'s own guard,
and the post-toggle guard in `_unhandled_input()` (six locations total).

Add the toggle handler right after `_toggle_quest_log()`, following its exact movement-pause
convention:

```gdscript
## Interactable Legend (2026-08-10 quest-system-and-tutorial design §9) -- bound to 'K'. Same
## toggle semantics as the other modal panels. Opening it also completes the tutorial's
## open_legend objective (unconditional — safe since the tutorial always auto-accepts first).
func _toggle_legend() -> void:
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open() or _talent_panel.visible or _inventory_panel.visible or _professions_panel.is_open() or _quest_log_panel.is_open():
		return
	if _legend_panel.is_open():
		_legend_panel.close()
		_pc.set_movement_paused(false)
	else:
		_legend_panel.open()
		_pc.set_movement_paused(true)
		_party_inventory.complete_objective(&"tutorial", &"open_legend")
```

Add its input check right after the existing `toggle_quest_log` check in `_unhandled_input()`:

```gdscript
	if event.is_action_pressed("toggle_interactable_legend"):
		_toggle_legend()
		return
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_legend.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.godot world/town_demo.gd tests/test_town_demo_legend.gd
git commit -m "feat(quests): wire the Interactable Legend into town_demo (K), completes open_legend"
```

---

### Task 6: Wire `InteractableLegendPanel` into `overworld_demo.gd`

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_demo_legend.gd`

**Interfaces:** identical shape to Task 5, applied to `overworld_demo.gd`. The
`toggle_interactable_legend` input action already exists (added in Task 5) — do not re-add it.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_overworld_demo_legend.gd
extends SceneTree

## Headless smoke test: Interactable Legend in overworld_demo.tscn (2026-08-10 quest-popups-and-
## tutorial-wiring plan Task 6), mirrors test_town_demo_legend.gd.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/overworld_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	inv.accept_quest(&"tutorial")

	_check(scene._legend_panel != null, "overworld_demo builds an InteractableLegendPanel")
	_check(not scene._legend_panel.is_open(), "Legend starts closed")

	scene._toggle_legend()
	_check(scene._legend_panel.is_open(), "_toggle_legend() opens the panel")
	_check(inv.is_objective_complete(&"tutorial", &"open_legend"), "opening the Legend completes the tutorial's open_legend objective")

	scene._toggle_legend()
	_check(not scene._legend_panel.is_open(), "_toggle_legend() again closes the panel")

	scene._toggle_legend()
	scene._toggle_professions()
	_check(scene._legend_panel.is_open(), "opening Professions while the Legend is open is blocked")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_legend.gd`
Expected: FAIL — `_legend_panel`/`_toggle_legend()` don't exist on `overworld_demo.gd` yet.

- [ ] **Step 3: Wire the panel**

Add the panel variable next to `_quest_log_panel`:

```gdscript
var _legend_panel: InteractableLegendPanel
```

Construct it right after the `_quest_log_panel` construction block:

```gdscript
	_legend_panel = InteractableLegendPanel.new()
	_legend_panel.position = Vector2(140, 60)
	_legend_panel.hide()
	ui.add_child(_legend_panel)
```

Add `or _legend_panel.is_open()` to every guard chain that currently checks
`_quest_log_panel.is_open()` — search for that exact string; it appears in `_toggle_inventory()`,
`_toggle_stats()`, `_toggle_talents()`, `_toggle_professions()`'s own guard, the `_process()`
interact-prompt-suppression guard, and the post-toggle guard in `_unhandled_input()` (six locations
total — this scene's guard set is one location more than town_demo's, matching the existing
difference in how Quest Log itself was wired into this scene vs. town_demo).

Add the toggle handler right after `_toggle_quest_log()`:

```gdscript
## Interactable Legend (2026-08-10 quest-system-and-tutorial design §9) -- bound to 'K'. Same
## toggle semantics as the other modal panels. Opening it also completes the tutorial's
## open_legend objective (unconditional — safe since the tutorial always auto-accepts first).
func _toggle_legend() -> void:
	if _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible or _inventory_panel.visible or _professions_panel.is_open() or _quest_log_panel.is_open():
		return
	if _legend_panel.is_open():
		_legend_panel.close()
		_pc.set_movement_paused(false)
	else:
		_legend_panel.open()
		_pc.set_movement_paused(true)
		_party_inventory.complete_objective(&"tutorial", &"open_legend")
```

Add its input check right after the existing `toggle_quest_log` check in `_unhandled_input()`:

```gdscript
	if event.is_action_pressed("toggle_interactable_legend"):
		_toggle_legend()
		return
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_legend.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_legend.gd
git commit -m "feat(quests): wire the Interactable Legend into overworld_demo (K)"
```

---

### Task 7: Wire `InteractableLegendPanel` into `dungeon_demo.gd`

**Files:**
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_dungeon_demo_legend.gd`

**Interfaces:** identical shape to Tasks 5-6, applied to `dungeon_demo.gd` (simpler guard set —
only Talents/Inventory/Professions/Quest Log exist here, matching how Quest Log itself was wired
into this scene).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_dungeon_demo_legend.gd
extends SceneTree

## Headless smoke test: Interactable Legend in dungeon_demo.tscn (2026-08-10 quest-popups-and-
## tutorial-wiring plan Task 7), mirrors test_town_demo_legend.gd.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/dungeon_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	inv.accept_quest(&"tutorial")

	_check(scene._legend_panel != null, "dungeon_demo builds an InteractableLegendPanel")
	_check(not scene._legend_panel.is_open(), "Legend starts closed")

	scene._toggle_legend()
	_check(scene._legend_panel.is_open(), "_toggle_legend() opens the panel")
	_check(inv.is_objective_complete(&"tutorial", &"open_legend"), "opening the Legend completes the tutorial's open_legend objective")

	scene._toggle_legend()
	_check(not scene._legend_panel.is_open(), "_toggle_legend() again closes the panel")

	scene._toggle_legend()
	scene._toggle_professions()
	_check(scene._legend_panel.is_open(), "opening Professions while the Legend is open is blocked")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_legend.gd`
Expected: FAIL — `_legend_panel`/`_toggle_legend()` don't exist on `dungeon_demo.gd` yet.

- [ ] **Step 3: Wire the panel**

Add the panel variable next to `_quest_log_panel`:

```gdscript
var _legend_panel: InteractableLegendPanel
```

Construct it right after the `_quest_log_panel` construction block:

```gdscript
	_legend_panel = InteractableLegendPanel.new()
	_legend_panel.position = Vector2(140, 60)
	_legend_panel.hide()
	ui.add_child(_legend_panel)
```

Add `or _legend_panel.is_open()` to every guard chain that currently checks
`_quest_log_panel.is_open()` — search for that exact string; it appears in the `_process()` guard,
the post-toggle guard in `_unhandled_input()`, `_toggle_inventory()`, `_toggle_stats()`,
`_toggle_talents()`, and `_toggle_professions()`'s own guard (six locations total).

Add the toggle handler right after `_toggle_quest_log()`:

```gdscript
## Interactable Legend (2026-08-10 quest-system-and-tutorial design §9) -- bound to 'K'. Same
## toggle semantics as the other modal panels. Opening it also completes the tutorial's
## open_legend objective (unconditional — safe since the tutorial always auto-accepts first).
func _toggle_legend() -> void:
	if _talent_panel.visible or _inventory_panel.visible or _professions_panel.is_open() or _quest_log_panel.is_open():
		return
	if _legend_panel.is_open():
		_legend_panel.close()
		_pc.set_movement_paused(false)
	else:
		_legend_panel.open()
		_pc.set_movement_paused(true)
		_party_inventory.complete_objective(&"tutorial", &"open_legend")
```

Add its input check right after the existing `toggle_quest_log` check in `_unhandled_input()`:

```gdscript
	if event.is_action_pressed("toggle_interactable_legend"):
		_toggle_legend()
		return
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_legend.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/dungeon_demo.gd tests/test_dungeon_demo_legend.gd
git commit -m "feat(quests): wire the Interactable Legend into dungeon_demo (K)"
```

---

### Task 8: Auto-start the tutorial quest

**Files:**
- Modify: `world/town_demo.gd`
- Test: `tests/test_town_demo_tutorial_autostart.gd`

**Interfaces:**
- Consumes: `PartyInventory.accepted_quest_ids`/`accept_quest()` (existing).
- Produces: a fresh `town_demo.tscn` load (no quests yet accepted) auto-accepts `&"tutorial"`.
  Every later task in this plan that wires an objective relies on the tutorial already being
  accepted by the time a player can reach that trigger.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_town_demo_tutorial_autostart.gd
extends SceneTree

## Headless test: a fresh town_demo.tscn load auto-accepts the tutorial quest (2026-08-10 quest-
## system-and-tutorial design §8's "auto-starts... every fresh launch" behavior).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	_check(inv.has_accepted_quest(&"tutorial"), "a fresh town_demo load auto-accepts the tutorial quest")
	_check(inv.is_quest_tracked(&"tutorial"), "the auto-accepted tutorial is tracked by default (accept_quest()'s existing behavior)")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_autostart.gd`
Expected: FAIL — nothing auto-accepts the tutorial yet.

- [ ] **Step 3: Add the auto-start**

In `world/town_demo.gd`'s `_ready()`, find the line `_party_inventory.round_down_jackpot_to_checkpoint()`
(the statement immediately after the `_build_inventory_demo()` call — this is the first point in
`_ready()` where `_party_inventory` is guaranteed non-null) and add immediately after it:

```gdscript
	# Tutorial auto-start (2026-08-10 quest-system-and-tutorial design §8): there's no save system,
	# so "no quests accepted yet" is an accurate proxy for "this is a fresh launch." Only wired here
	# (town_demo is the real entry point this project's playtests actually launch) — not duplicated
	# into overworld_demo/dungeon_demo, since accept_quest() would just no-op there anyway once this
	# has already run.
	if _party_inventory.accepted_quest_ids.is_empty():
		_party_inventory.accept_quest(&"tutorial")
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_autostart.gd`
Expected: PASS.

Also re-run `tests/test_lost_cat_board_flow.gd` and `tests/test_lost_cat_quest_full_sequence.gd` to
confirm the tutorial auto-accepting doesn't interfere with Lost Cat's own flow (it shouldn't — they're
independent quest ids and independent `accepted_quest_ids` entries).
Expected: both still PASS.

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd tests/test_town_demo_tutorial_autostart.gd
git commit -m "feat(quests): auto-start the tutorial quest on a fresh town_demo load"
```

---

### Task 9: Wire the `move` tutorial objective

**Files:**
- Modify: `world/pc_controller.gd`
- Modify: `world/town_demo.gd`
- Modify: `world/overworld_demo.gd`
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_pc_controller_moved_signal.gd`

**Interfaces:**
- Produces: `PCController.moved` signal, emitted exactly once, the first time
  `_physics_process()` observes nonzero movement input. All three scenes connect it once to
  complete the tutorial's `move` objective.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_pc_controller_moved_signal.gd
extends SceneTree

## Headless test for PCController's new `moved` signal (2026-08-10 quest-popups-and-tutorial-wiring
## plan Task 9) — fires exactly once, on the first nonzero movement input.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var pc := PCController.new()
	var fire_count_box: Array = [0]
	pc.moved.connect(func() -> void: fire_count_box[0] += 1)

	# Zero input: no signal.
	Input.action_press("move_right")
	Input.action_release("move_right")
	pc._physics_process(0.016)
	_check(fire_count_box[0] == 0, "no signal on a frame with zero net movement input")

	# Nonzero input: fires once.
	Input.action_press("move_right")
	pc._physics_process(0.016)
	_check(fire_count_box[0] == 1, "fires once on the first nonzero movement input (got %d)" % fire_count_box[0])

	# Stays fired — doesn't re-fire on subsequent nonzero-input frames.
	pc._physics_process(0.016)
	_check(fire_count_box[0] == 1, "does not fire again on a later nonzero-input frame (got %d)" % fire_count_box[0])

	Input.action_release("move_right")
	pc.free()
	print(("PC CONTROLLER MOVED SIGNAL TEST PASSED" if _failures == 0 else "PC CONTROLLER MOVED SIGNAL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_pc_controller_moved_signal.gd`
Expected: FAIL — `moved` signal doesn't exist yet.

- [ ] **Step 3: Add the signal to `PCController`, connect it in all 3 scenes**

In `world/pc_controller.gd`, add near the top of the class (after the `@export var move_speed`
line):

```gdscript
## Emitted exactly once, the first time _physics_process() observes nonzero movement input — the
## tutorial's "move" objective hook (2026-08-10 quest-popups-and-tutorial-wiring plan Task 9).
signal moved

var _moved_signal_fired: bool = false
```

Replace `_physics_process()`:

```gdscript
func _physics_process(_delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if not _moved_signal_fired and input_vector != Vector2.ZERO:
		_moved_signal_fired = true
		moved.emit()
	velocity = movement_velocity(input_vector, move_speed, _movement_paused)
	move_and_slide()
```

In each of `world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd`: find where
`_pc` is constructed/configured (search for `_pc = PCController.new()` or wherever the scene
finishes setting up its `_pc` field) and add, right after `_party_inventory` is guaranteed to
exist (in `town_demo.gd`, this must come after the tutorial auto-start line from Task 8, so the
quest exists before this connection could ever fire against it — connecting the signal itself is
harmless either way, since nothing emits it until the player actually moves):

```gdscript
	_pc.moved.connect(func() -> void: _party_inventory.complete_objective(&"tutorial", &"move"))
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_pc_controller_moved_signal.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/pc_controller.gd world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_pc_controller_moved_signal.gd
git commit -m "feat(quests): wire the tutorial's move objective to PCController's first movement"
```

---

### Task 10: Wire the `open_inventory` and `equip_gear` tutorial objectives

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Modify: `world/town_demo.gd`
- Modify: `world/overworld_demo.gd`
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_inventory_menu_panel_tutorial_objectives.gd`

**Interfaces:**
- Consumes: `InventoryMenuPanel._party_inventory` (existing member, set in `open_for()`),
  `_equip_selected`/`_auto_equip_onto_pc` (existing methods).
- Produces: opening `InventoryMenuPanel` in any of the 3 scenes completes `open_inventory`;
  equipping a piece of Gear via either equip path completes `equip_gear`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_inventory_menu_panel_tutorial_objectives.gd
extends SceneTree

## Headless test: equipping gear through InventoryMenuPanel completes the tutorial's equip_gear
## objective (2026-08-10 quest-popups-and-tutorial-wiring plan Task 10). The open_inventory half of
## this task is covered by the 3 scene-level tests in this same task's Step 1 addendum below.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()
	inv.accept_quest(&"tutorial")
	var pc := Combatant.new()
	pc.is_player = true
	var gear := Gear.new()
	gear.display_name = "Test Helm"
	gear.slot = Gear.Slot.HEADWEAR
	inv.give_gear(gear)

	var panel := InventoryMenuPanel.new()
	var vault := Vault.new()
	panel.open_for(pc, [], inv, vault, true)
	_check(not inv.is_objective_complete(&"tutorial", &"equip_gear"), "equip_gear isn't complete before any equip happens")

	panel.select_item_for_test(gear, false)
	panel.equip_selected_for_test(pc, panel.gear_slot_index_for(gear.slot))
	_check(inv.is_objective_complete(&"tutorial", &"equip_gear"), "equipping a piece of Gear completes the tutorial's equip_gear objective")

	panel.free()
	print(("INVENTORY MENU PANEL TUTORIAL OBJECTIVES TEST PASSED" if _failures == 0 else "INVENTORY MENU PANEL TUTORIAL OBJECTIVES TEST FAILED: %d" % _failures))
	quit(_failures)
```

**Note for the implementer:** this test assumes `select_item_for_test(item, is_weapon)` and
`equip_selected_for_test(c, slot_idx)` test hooks exist (or are trivial one-line wrappers around
the existing private `_selected` field and `_equip_selected()` — check `inventory_menu_panel.gd`
for existing test hooks with similar names first, e.g. anything calling `_equip_selected` from a
`_for_test()` wrapper already, and reuse it rather than adding a duplicate). If no such hook
exists at all, add a minimal one:
```gdscript
func select_item_for_test(item: Resource, is_weapon: bool) -> void:
	_selected = {"item": item, "is_weapon": is_weapon}

func equip_selected_for_test(c: Combatant, slot_idx: int) -> void:
	_equip_selected(c, slot_idx)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_tutorial_objectives.gd`
Expected: FAIL — equipping doesn't complete the objective yet (and the test-hook methods may not
exist yet either, if none were found to reuse).

- [ ] **Step 3: Wire `equip_gear`, then `open_inventory` in all 3 scenes**

In `combat/ui/inventory_menu_panel.gd`, in `_equip_selected()` (currently ends with
`_equip_reject_message = ""` then `_selected = {}`), add the completion call right before those
final two lines, inside the successful-gear-equip branch (the `else:` branch that calls
`c.equip_gear(item)` — NOT inside the weapon-equip `if is_weapon:` branch, since "equip a piece of
gear" per the spec means Gear specifically, not weapons):

```gdscript
		_active_container_take_gear(item)
		var displaced2: Gear = c.equip_gear(item)
		if displaced2 != null:
			_active_container_give_gear(displaced2)
		_party_inventory.complete_objective(&"tutorial", &"equip_gear")
	_equip_reject_message = ""
	_selected = {}
```

Do the same in `_auto_equip_onto_pc()` (the double-click auto-equip path) — find its Gear-equip
branch (mirrors `_equip_selected`'s shape) and add the identical
`_party_inventory.complete_objective(&"tutorial", &"equip_gear")` call right after its
`c.equip_gear(item)` call, inside the Gear (non-weapon) branch only.

In each of `world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd`'s
`_toggle_inventory()`, add the objective-completion call to the `else:` (opening) branch, right
after the existing `_inventory_panel.open_for(...)` call:

```gdscript
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, true)   # (town_demo's exact existing line — overworld/dungeon have their own equivalent open_for() call with their own arguments; add the next line after whichever open_for() call already exists in that scene's _toggle_inventory())
		_pc.set_movement_paused(true)
		_party_inventory.complete_objective(&"tutorial", &"open_inventory")
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_tutorial_objectives.gd`
Expected: PASS.

Manually sanity-check `open_inventory` by re-running each scene's existing inventory smoke test
(e.g. `tests/test_town_demo_inventory.gd`, `tests/test_overworld_demo_inventory.gd` if present) to
confirm nothing else broke — the new line doesn't change any existing return value or control flow.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_inventory_menu_panel_tutorial_objectives.gd
git commit -m "feat(quests): wire the tutorial's open_inventory and equip_gear objectives"
```

---

### Task 11: Wire the `open_event_log` and `open_professions` tutorial objectives

**Files:**
- Modify: `world/town_demo.gd`
- Modify: `world/overworld_demo.gd`
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_town_demo_tutorial_panel_objectives.gd`

**Interfaces:**
- Produces: opening the Event Log (`L`) or Professions (`P`) panel in any of the 3 scenes
  completes the corresponding tutorial objective.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_town_demo_tutorial_panel_objectives.gd
extends SceneTree

## Headless test: opening the Event Log or Professions panel completes the matching tutorial
## objective (2026-08-10 quest-popups-and-tutorial-wiring plan Task 11). town_demo only — the same
## wiring pattern is applied identically to overworld_demo/dungeon_demo, covered by their own
## existing panel-toggle smoke tests continuing to pass (re-run in Step 4).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory

	_check(not inv.is_objective_complete(&"tutorial", &"open_event_log"), "open_event_log isn't complete yet")
	scene._event_log_panel.visible = false   # ensure the next toggle is an OPEN transition
	var event := InputEventAction.new()
	event.action = &"toggle_event_log"
	event.pressed = true
	scene._unhandled_input(event)
	_check(scene._event_log_panel.visible, "the Event Log opened")
	_check(inv.is_objective_complete(&"tutorial", &"open_event_log"), "opening the Event Log completes open_event_log")

	_check(not inv.is_objective_complete(&"tutorial", &"open_professions"), "open_professions isn't complete yet")
	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "Professions opened")
	_check(inv.is_objective_complete(&"tutorial", &"open_professions"), "opening Professions completes open_professions")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_panel_objectives.gd`
Expected: FAIL — neither objective completes yet.

- [ ] **Step 3: Wire both objectives in all 3 scenes**

In each of `world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd`'s
`_unhandled_input()`, find the `toggle_event_log` check (the line
`_event_log_panel.visible = not _event_log_panel.visible`) and change it to only complete the
objective on the OPEN transition:

```gdscript
	if event.is_action_pressed("toggle_event_log"):
		_event_log_panel.visible = not _event_log_panel.visible
		if _event_log_panel.visible:
			_party_inventory.complete_objective(&"tutorial", &"open_event_log")
		return
```

In each of the same 3 files' `_toggle_professions()`, add the completion call to the `else:`
(opening) branch, right after the existing `_professions_panel.open_for(_party_inventory)` call:

```gdscript
	else:
		_professions_panel.open_for(_party_inventory)
		_pc.set_movement_paused(true)
		_party_inventory.complete_objective(&"tutorial", &"open_professions")
```

- [ ] **Step 4: Refresh the class cache, then run the tests to verify they pass**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_panel_objectives.gd`
Expected: PASS.

Re-run each scene's existing Event Log and Professions smoke tests (e.g.
`tests/test_overworld_demo_professions.gd`, `tests/test_dungeon_demo_professions.gd`) to confirm
the new lines didn't change any existing behavior.
Expected: all still PASS.

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_town_demo_tutorial_panel_objectives.gd
git commit -m "feat(quests): wire the tutorial's open_event_log and open_professions objectives"
```

---

### Task 12: Wire the `visit_shop` objective and the Shopkeeper's tutorial dialogue

**Files:**
- Modify: `world/town_demo.gd`
- Test: `tests/test_town_demo_tutorial_shop_dialogue.gd`

**Interfaces:**
- Produces: while the tutorial's `visit_shop` objective is incomplete, talking to the Shopkeeper
  plays a tutorial-specific `DialogueSet` (Amber + rarity explainer) instead of the normal
  greeting, and completes the objective. Once complete, later visits play the normal greeting.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_town_demo_tutorial_shop_dialogue.gd
extends SceneTree

## Headless test: the Shopkeeper's tutorial-only dialogue plays while visit_shop is incomplete,
## and completes the objective; the normal greeting resumes afterward (2026-08-10 quest-popups-
## and-tutorial-wiring plan Task 12).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	_check(not inv.is_objective_complete(&"tutorial", &"visit_shop"), "visit_shop isn't complete yet")

	var shopkeeper: Villager = null
	for child in scene._interior.get_children():
		if child is Villager and (child as Villager).is_vendor:
			shopkeeper = child
	_check(shopkeeper != null, "found the Shopkeeper Villager")

	scene._on_vendor_interacted(shopkeeper.dialogue, shopkeeper)
	_check(scene._vendor_prompt_panel.is_open(), "the vendor prompt opened")
	# The tutorial dialogue text is whatever the handler builds — inspect via the prompt panel's
	# own dialogue_set (check its actual field/hook name in vendor_prompt_panel.gd if this doesn't
	# match; the point is the FIRST line's text mentions Amber, not the normal greeting).
	_check(inv.is_objective_complete(&"tutorial", &"visit_shop"), "talking to the Shopkeeper while visit_shop is pending completes it")

	# A second visit, now that the objective is complete, should NOT re-show tutorial-only content —
	# verified indirectly: is_objective_complete stays true (no regression), and a second call
	# doesn't error.
	scene._on_vendor_interacted(shopkeeper.dialogue, shopkeeper)
	_check(inv.is_objective_complete(&"tutorial", &"visit_shop"), "a later visit doesn't un-complete the objective")

	quit()
```

**Note for the implementer:** find the exact field/method `VendorPromptPanel` exposes for reading
back which `DialogueSet` it was opened with (or its rendered text), and adjust the middle assertion
above to actually check the tutorial line's content (e.g. `.contains("Amber")`) once you know that
panel's real test-hook shape — the important, non-negotiable behavior is: while `visit_shop` is
incomplete, the Shopkeeper's dialogue differs from its own `dialogue` field's normal greeting, and
the objective completes; once complete, the normal `dialogue_set` parameter passed in is used as-is.

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_shop_dialogue.gd`
Expected: FAIL — `visit_shop` never completes yet.

- [ ] **Step 3: Wire the dialogue swap and completion**

In `world/town_demo.gd`, add a new helper right after `_make_dialogue()`:

```gdscript
## The Shopkeeper's tutorial-only greeting (2026-08-10 quest-system-and-tutorial design §8) —
## explains the Amber economy and item-rarity coloring, shown instead of the normal greeting while
## the tutorial's visit_shop objective is still pending. Built the same way as _make_dialogue().
func _make_shopkeeper_tutorial_dialogue(speaker_name: String) -> DialogueSet:
	var line1 := DialogueLine.new()
	line1.speaker_name = speaker_name
	line1.text = "New around here? Everything in my shop costs Amber — you'll earn it from quests and selling loot."
	var line2 := DialogueLine.new()
	line2.speaker_name = speaker_name
	line2.text = "And take a look at the color on an item's name — that's its rarity. Brighter, fancier colors mean a better find."
	var farewell := DialogueLine.new()
	farewell.speaker_name = speaker_name
	farewell.text = "Take a look around, and come back anytime!"
	var lines: Array[DialogueLine] = [line1, line2, farewell]
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	return dialogue_set
```

Replace `_on_vendor_interacted()`:

```gdscript
## WoW-style vendor front door (2026-07-17 general store design §3.6): the Shopkeeper's interact
## opens a Talk/Shop/Leave prompt instead of jumping straight into dialogue. While the tutorial's
## visit_shop objective is pending, swaps in a tutorial-only greeting (2026-08-10 §8) and completes
## the objective instead of playing the passed-in dialogue_set.
func _on_vendor_interacted(dialogue_set: DialogueSet, villager: Villager) -> void:
	_talking_to = villager
	villager.set_wander_paused(true)
	_pc.set_movement_paused(true)
	var set_to_show: DialogueSet = dialogue_set
	if not _party_inventory.is_objective_complete(&"tutorial", &"visit_shop"):
		set_to_show = _make_shopkeeper_tutorial_dialogue(villager.dialogue.lines[0].speaker_name if not villager.dialogue.lines.is_empty() else "Shopkeeper")
		_party_inventory.complete_objective(&"tutorial", &"visit_shop")
	_vendor_prompt_panel.open_for(set_to_show)
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_shop_dialogue.gd`
Expected: PASS. Adjust the test's middle assertion per the implementer note in Step 1 once you
confirm `VendorPromptPanel`'s real test-hook shape, then re-run.

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd tests/test_town_demo_tutorial_shop_dialogue.gd
git commit -m "feat(quests): wire the tutorial's visit_shop objective + Shopkeeper Amber/rarity dialogue"
```

---

### Task 13: Wire the `win_fight` objective

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_combat_tutorial_win_fight_objective.gd`

**Interfaces:**
- Produces: winning a handoff-launched fight (`_arrived_via_handoff == true`, real
  `_party_inventory` present) completes the tutorial's `win_fight` objective.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_combat_tutorial_win_fight_objective.gd
extends SceneTree

## Headless test: winning a real (handoff-launched) fight completes the tutorial's win_fight
## objective (2026-08-10 quest-popups-and-tutorial-wiring plan Task 13). Mirrors the existing
## _on_combat_ended-adjacent test conventions in this file's sibling combat tests — construct a
## minimal combat.gd instance, populate the fields _on_combat_ended() reads, and call it directly
## rather than driving a full spin-to-win sequence.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var combat: Node = load("res://combat/combat.tscn").instantiate()
	get_root().add_child(combat)
	await process_frame

	var inv := PartyInventory.new()
	inv.accept_quest(&"tutorial")
	combat._party_inventory = inv
	combat._arrived_via_handoff = true
	combat._pcs = []
	combat._enemies = []
	combat._panels = {}

	_check(not inv.is_objective_complete(&"tutorial", &"win_fight"), "win_fight isn't complete before any victory")
	combat._on_combat_ended(true)
	_check(inv.is_objective_complete(&"tutorial", &"win_fight"), "winning a handoff-launched fight completes win_fight")

	# A loss must NOT complete it.
	var inv2 := PartyInventory.new()
	inv2.accept_quest(&"tutorial")
	combat._party_inventory = inv2
	combat._on_combat_ended(false)
	_check(not inv2.is_objective_complete(&"tutorial", &"win_fight"), "losing a fight does not complete win_fight")

	quit()
```

**Note for the implementer:** if any of `_party_inventory`/`_arrived_via_handoff`/`_pcs`/
`_enemies`/`_panels` aren't directly settable from outside (private-by-convention but this
codebase's tests routinely set fields directly on a bare instantiated scene, per
`test_town_demo_quest_log.gd`'s established convention) or `_on_combat_ended()` reads additional
fields not listed here (e.g. `_fight_xp_gained`, `_fight_loot_names`) that error on being unset,
initialize those to their natural empty/zero defaults (`0`, `[]`) before calling it — the test only
cares about the win_fight completion behavior, not the full result-card rendering.

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_tutorial_win_fight_objective.gd`
Expected: FAIL — `win_fight` never completes yet.

- [ ] **Step 3: Wire the completion**

In `combat/combat.gd`'s `_on_combat_ended(winner_is_player: bool)`, add near the top of the
function (right after the existing loop that clears combat effects, before `_last_result_won` is
set):

```gdscript
	if winner_is_player and _arrived_via_handoff and _party_inventory != null:
		_party_inventory.complete_objective(&"tutorial", &"win_fight")
```

- [ ] **Step 4: Refresh the class cache, then run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_tutorial_win_fight_objective.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_combat_tutorial_win_fight_objective.gd
git commit -m "feat(quests): wire the tutorial's win_fight objective to a real combat victory"
```

---

### Task 14: Full tutorial end-to-end integration test

**Files:**
- Test: `tests/test_tutorial_full_sequence.gd`

**Interfaces:**
- Consumes: everything built in Tasks 1-13. This task adds no production code — it's the
  integration proof that the whole chain (auto-start → all 8 objectives → auto-complete → reward)
  actually works together against a real `town_demo.tscn` instance, mirroring
  `tests/test_lost_cat_quest_full_sequence.gd`'s shape.

- [ ] **Step 1: Write the test**

```gdscript
# tests/test_tutorial_full_sequence.gd
extends SceneTree

## Full end-to-end integration test for the tutorial quest (2026-08-10 quest-system-and-tutorial
## design) — proves every piece built across this plan's 13 tasks works TOGETHER: auto-start on a
## fresh town_demo load → each of the 8 objectives completing via its real trigger → auto-complete
## → reward_amber granted. Mirrors test_lost_cat_quest_full_sequence.gd's shape.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	_check(inv.has_accepted_quest(&"tutorial"), "1. auto-started on load")
	var amber_before: int = inv.amber

	# 2. move
	Input.action_press("move_right")
	scene._pc._physics_process(0.016)
	Input.action_release("move_right")
	_check(inv.is_objective_complete(&"tutorial", &"move"), "2. move objective complete")

	# 3. open_inventory
	scene._toggle_inventory()
	_check(inv.is_objective_complete(&"tutorial", &"open_inventory"), "3. open_inventory objective complete")
	scene._toggle_inventory()

	# 4. equip_gear
	var gear := Gear.new()
	gear.display_name = "Tutorial Test Cap"
	gear.slot = Gear.Slot.HEADWEAR
	inv.give_gear(gear)
	scene._inventory_panel.select_item_for_test(gear, false)
	scene._inventory_panel.equip_selected_for_test(scene._pc_combatant, scene._inventory_panel.gear_slot_index_for(gear.slot))
	_check(inv.is_objective_complete(&"tutorial", &"equip_gear"), "4. equip_gear objective complete")

	# 5. open_event_log
	var log_event := InputEventAction.new()
	log_event.action = &"toggle_event_log"
	log_event.pressed = true
	scene._event_log_panel.visible = false
	scene._unhandled_input(log_event)
	_check(inv.is_objective_complete(&"tutorial", &"open_event_log"), "5. open_event_log objective complete")

	# 6. open_professions
	scene._toggle_professions()
	_check(inv.is_objective_complete(&"tutorial", &"open_professions"), "6. open_professions objective complete")
	scene._toggle_professions()

	# 7. open_legend
	scene._toggle_legend()
	_check(inv.is_objective_complete(&"tutorial", &"open_legend"), "7. open_legend objective complete")
	scene._toggle_legend()

	# 8. visit_shop
	var shopkeeper: Villager = null
	for child in scene._interior.get_children():
		if child is Villager and (child as Villager).is_vendor:
			shopkeeper = child
	scene._on_vendor_interacted(shopkeeper.dialogue, shopkeeper)
	_check(inv.is_objective_complete(&"tutorial", &"visit_shop"), "8. visit_shop objective complete")
	_check(not inv.has_completed_quest(&"tutorial"), "still not complete — win_fight is the last objective")

	# 9. win_fight — the final objective; completing it must auto-complete the quest and grant the
	# reward. town_demo has no _on_combat_ended of its own (that's combat.gd, exercised directly by
	# Task 13's own test) — call PartyInventory the same way that real hook does, to prove the
	# auto-complete/reward chain fires from the LAST objective regardless of which trigger reaches it.
	inv.complete_objective(&"tutorial", &"win_fight")
	_check(inv.is_objective_complete(&"tutorial", &"win_fight"), "9. win_fight objective complete")
	_check(inv.has_completed_quest(&"tutorial"), "completing the last objective auto-completes the tutorial quest")

	var tutorial_quest: Quest = QuestLibrary.get_quest(&"tutorial")
	_check(inv.amber == amber_before + tutorial_quest.reward_amber, "completing the tutorial grants its reward_amber (got %d, expected %d)" % [inv.amber, amber_before + tutorial_quest.reward_amber])

	quit()
```

- [ ] **Step 2: Run test to verify it fails before Tasks 1-13 exist**

(This step is retroactive — if you're implementing this plan in order, Tasks 1-13 already exist by
the time you reach this task, so this test should already PASS on first run. If it fails, that
means one of the earlier tasks' wiring has a real gap this integration test caught — treat any
failure here as a bug in an earlier task, not something to "fix" by weakening this test.)

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_tutorial_full_sequence.gd`
Expected: PASS (or a specific, diagnosable failure pointing at a real gap in an earlier task).

- [ ] **Step 3: N/A — no production code in this task**

- [ ] **Step 4: Confirm the full suite of this plan's own tests are still green**

Run each of this plan's test files once more in sequence to confirm nothing regressed:
`test_party_inventory_quest_state.gd`, `test_quest_popup_panel.gd`, `test_lost_cat_board_flow.gd`,
`test_lost_cat_quest_full_sequence.gd`, `test_interactable_legend_panel.gd`,
`test_town_demo_legend.gd`, `test_overworld_demo_legend.gd`, `test_dungeon_demo_legend.gd`,
`test_town_demo_tutorial_autostart.gd`, `test_pc_controller_moved_signal.gd`,
`test_inventory_menu_panel_tutorial_objectives.gd`, `test_town_demo_tutorial_panel_objectives.gd`,
`test_town_demo_tutorial_shop_dialogue.gd`, `test_combat_tutorial_win_fight_objective.gd`,
`test_tutorial_full_sequence.gd`.
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/test_tutorial_full_sequence.gd
git commit -m "test(quests): add full tutorial end-to-end integration test"
```

---

## After this plan

The tutorial is fully playable end to end (auto-start through all 8 real-triggered objectives to
completion + reward), and Lost Cat's board flow now goes through the same `QuestPopupPanel`
machinery. What remains for Plan 3, per the spec's split (with the Interactable Legend now already
delivered here instead): `WorldTooltip` + `Interactable.hover_description` for the Old Well/Board/
Shop (spec §10), and the "Respawn Gathering Nodes" debug utility (spec §12).
