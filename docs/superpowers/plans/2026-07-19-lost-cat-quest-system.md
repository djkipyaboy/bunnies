# Lost Cat Quest System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Adventuring Board's placeholder "Lost Cat" entry into the game's first real quest:
accept it in town, rescue the cat ("Whiskers") by defeating The Hollow Warden on dungeon floor 4,
carry it back, and turn it in at the board for a flavor-only Thank You Note that names the current
party.

**Architecture:** Almost every piece reuses an existing, already-proven pattern in this codebase —
`PartyInventory`'s existing `mark`/`has` array-pair convention (already used for `quest_items`), the
Adventuring Board's already-emitted-but-unconsumed `entry_selected` signal, the dungeon's existing
`is_defeated`/`mark_defeated`/no-respawn-on-rebuild convention, and the Amber HUD's exact
placement/refresh shape for a new on-screen tracker. Two small new pieces: a `CagedCat` Interactable
with genuinely different pre/post-rescue behavior, and Button-based Quest Items tab rows (mirroring
the Materials tab's existing pattern) for the Thank You Note's dialogue interactivity.

**Tech Stack:** Godot 4.6.3-stable, GDScript only, static typing throughout.

## Global Constraints

- **Engine: Godot 4.6+ (4.6.3-stable). Language: GDScript only** — no C#.
- **Prefer static typing** (typed vars, typed function signatures).
- **Default to writing no comments.** Only add one when the WHY is non-obvious.
- Test convention: headless `extends SceneTree` scripts under `tests/test_*.gd`, run via
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  from the `bunnies/` project root. Exit code 0 = all checks passed — never grep stdout for "FAIL".
  Every test MUST use a `_failures: int = 0` counter incremented (with `push_error`) inside its
  `_check()` helper, ending with `quit(_failures)` — **never a bare `quit()`**. This exact bug (a test
  that always exits 0 regardless of real pass/fail) recurred independently 3 times in this project's
  immediately-prior Hollow Warden plan; it must not recur here.
- **If a test instantiates `combat.tscn` or any driving scene, type the local variable holding it as
  that scene's real `class_name`** (e.g. `Combat`, `Town` — check the scene script's own `class_name`
  line), never `Node`. Assigning a typed-array property (e.g. `Array[QuestBoardEntry]`) through a
  `Node`-typed handle silently aborts the frame with an uncaught SCRIPT ERROR that doesn't propagate
  to the failure count — a documented, previously-recurring gotcha in this codebase.
- **After adding/changing a `class_name`-visible symbol**, refresh the project's class cache before
  running a headless test that references it:
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
- **Git commit hygiene**: this repository's working tree has unrelated pre-existing UNTRACKED files
  sitting in it from other in-progress work. Always `git add` the EXACT files a task changed, by
  name — never `git add -A` or `git add .`.
- Spec: `docs/superpowers/specs/2026-07-19-lost-cat-quest-system-design.md` (read this first for full
  architectural rationale — every code sample in this plan is drawn directly from it).

---

### Task 1: `PartyInventory` quest-state tracking

**Files:**
- Modify: `economy/resources/party_inventory.gd`
- Test: `tests/test_party_inventory_quest_state.gd` (new)

**Interfaces:**
- Produces: `PartyInventory.accepted_quest_ids: Array[StringName]`,
  `completed_quest_ids: Array[StringName]`, `accept_quest(quest_id: StringName) -> void`,
  `has_accepted_quest(quest_id: StringName) -> bool`, `complete_quest(quest_id: StringName) -> void`,
  `has_completed_quest(quest_id: StringName) -> bool`.
- Consumed by: Task 3 (board state branching + accept/turn-in), Task 5 (on-screen tracker).

- [ ] **Step 1: Write the failing test**

Create `tests/test_party_inventory_quest_state.gd`:

```gdscript
extends SceneTree

## Headless test for PartyInventory's new quest-state tracking (spec 2026-07-19 §3.1) — mirrors the
## existing mark_defeated/is_defeated array-pair convention already used elsewhere in this codebase.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(inv.accepted_quest_ids.is_empty(), "accepted_quest_ids starts empty")
	_check(inv.completed_quest_ids.is_empty(), "completed_quest_ids starts empty")
	_check(not inv.has_accepted_quest(&"lost_cat"), "has_accepted_quest is false before accepting")

	inv.accept_quest(&"lost_cat")
	_check(inv.has_accepted_quest(&"lost_cat"), "has_accepted_quest is true after accepting")
	_check(not inv.has_completed_quest(&"lost_cat"), "has_completed_quest is still false — accepting isn't completing")
	inv.accept_quest(&"lost_cat")
	_check(inv.accepted_quest_ids.size() == 1, "accepting the same quest twice doesn't duplicate the entry (got %d)" % inv.accepted_quest_ids.size())

	inv.complete_quest(&"lost_cat")
	_check(inv.has_completed_quest(&"lost_cat"), "has_completed_quest is true after completing")
	_check(inv.has_accepted_quest(&"lost_cat"), "has_accepted_quest STAYS true after completing (both records persist)")
	inv.complete_quest(&"lost_cat")
	_check(inv.completed_quest_ids.size() == 1, "completing the same quest twice doesn't duplicate the entry (got %d)" % inv.completed_quest_ids.size())

	_check(not inv.has_accepted_quest(&"some_other_quest"), "a different quest id is unaffected")

	print(("PARTY INVENTORY QUEST STATE TEST PASSED" if _failures == 0 else "PARTY INVENTORY QUEST STATE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: FAIL — none of these fields/methods exist yet.

- [ ] **Step 3: Add the quest-state fields/methods to `economy/resources/party_inventory.gd`**

Add these immediately after the existing `unlocked_companion_slots` field declaration:
```gdscript
@export var accepted_quest_ids: Array[StringName] = []
@export var completed_quest_ids: Array[StringName] = []
```
Add these new methods immediately after the existing `consume_quest_item()` method (at the end of
the file):
```gdscript
func accept_quest(quest_id: StringName) -> void:
	if not accepted_quest_ids.has(quest_id):
		accepted_quest_ids.append(quest_id)

func has_accepted_quest(quest_id: StringName) -> bool:
	return accepted_quest_ids.has(quest_id)

func complete_quest(quest_id: StringName) -> void:
	if not completed_quest_ids.has(quest_id):
		completed_quest_ids.append(quest_id)

func has_completed_quest(quest_id: StringName) -> bool:
	return completed_quest_ids.has(quest_id)
```

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Commit**

```bash
git add economy/resources/party_inventory.gd tests/test_party_inventory_quest_state.gd
git commit -m "feat(economy): add PartyInventory quest-state tracking (accept/complete)"
```

---

### Task 2: `QuestBoardEntry` gains a real id

**Files:**
- Modify: `world/resources/quest_board_entry.gd`
- Modify: `tests/test_quest_board_entry.gd`

**Interfaces:**
- Produces: `QuestBoardEntry.id: StringName`.
- Consumed by: Task 3 (board state branching, `entry_selected` handling).

- [ ] **Step 1: Read the existing test**

Read `tests/test_quest_board_entry.gd` in full to see its current shape and conventions before
extending it.

- [ ] **Step 2: Add a failing assertion**

Add this check to `tests/test_quest_board_entry.gd` (wherever a fresh `QuestBoardEntry` is
constructed and checked — follow the file's existing style):
```gdscript
	var entry := QuestBoardEntry.new()
	_check(entry.id == &"", "QuestBoardEntry.id defaults to empty StringName (got %s)" % entry.id)
	entry.id = &"lost_cat"
	_check(entry.id == &"lost_cat", "QuestBoardEntry.id can be set to a real quest id")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_board_entry.gd`
Expected: FAIL — `QuestBoardEntry.id` doesn't exist yet.

- [ ] **Step 4: Add the field to `world/resources/quest_board_entry.gd`**

Add this immediately after the existing `body_text` field:
```gdscript
@export var id: StringName = &""
```

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_board_entry.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Commit**

```bash
git add world/resources/quest_board_entry.gd tests/test_quest_board_entry.gd
git commit -m "feat(world): add QuestBoardEntry.id for real quest identification"
```

---

### Task 3: Board interactivity — accept, track, turn in

**Files:**
- Modify: `world/town_demo.gd`
- Test: `tests/test_lost_cat_board_flow.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.accept_quest`/`has_accepted_quest`/`complete_quest`/`has_completed_quest`
  (Task 1), `QuestBoardEntry.id` (Task 2), `PartyInventory.give_quest_item`/`has_quest_item`/
  `consume_quest_item` (pre-existing, from the lock-and-key work).
- Produces: `_make_quest_entries()` state-branches the Lost Cat entry; a new
  `_on_board_entry_selected(entry: QuestBoardEntry) -> void` handler wired to
  `AdventuringBoardPanel.entry_selected`; a new `_make_thank_you_note() -> QuestItem` helper.
- Consumed by: Task 5 (tracker reads the same quest-state methods), Task 6 (the Thank You Note this
  task grants).

- [ ] **Step 1: Write the failing test**

Create `tests/test_lost_cat_board_flow.gd`:

```gdscript
extends SceneTree

## Headless test for the Lost Cat quest's board interactivity (spec 2026-07-19 §3.3): clicking the
## unaccepted row accepts it and re-renders with CURRENT-category "bring it back" text; clicking it
## again while accepted but not holding the rescued cat is a no-op; clicking it while holding the
## rescued cat consumes the item, completes the quest, and grants the Thank You Note; clicking a
## completed quest again is a no-op; the other 2 placeholder rows (empty id) are always no-ops.

var _instance: TownDemo
var _failures: int = 0

func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate() as Town
	root.add_child(_instance)
	await process_frame
	await process_frame

	var town: TownDemo = _instance
	var inv: PartyInventory = town._party_inventory

	# Not yet accepted: the Lost Cat entry has category SIDE and the flavor-pitch text.
	var entries: Array[QuestBoardEntry] = town._make_quest_entries()
	var lost_cat: QuestBoardEntry = null
	for e: QuestBoardEntry in entries:
		if e.id == &"lost_cat":
			lost_cat = e
	_check(lost_cat != null, "the Lost Cat entry exists with id lost_cat")
	_check(lost_cat.category == QuestBoardEntry.Category.SIDE, "Lost Cat starts as a SIDE quest")
	_check(not inv.has_accepted_quest(&"lost_cat"), "Lost Cat starts unaccepted")

	# Click it: accepts.
	town._on_board_entry_selected(lost_cat)
	_check(inv.has_accepted_quest(&"lost_cat"), "clicking the unaccepted row accepts it")
	entries = town._make_quest_entries()
	for e: QuestBoardEntry in entries:
		if e.id == &"lost_cat":
			lost_cat = e
	_check(lost_cat.category == QuestBoardEntry.Category.CURRENT, "Lost Cat becomes CURRENT once accepted")
	_check(lost_cat.body_text.to_lower().contains("bring"), "Lost Cat's accepted body text reminds the player to bring the cat back")

	# Click it again (accepted, not holding the item yet): no-op.
	town._on_board_entry_selected(lost_cat)
	_check(not inv.has_completed_quest(&"lost_cat"), "clicking an accepted-but-not-ready quest again does nothing")
	_check(not inv.has_quest_item(&"thank_you_note"), "no Thank You Note yet")

	# Now the player holds the rescued cat — click again: turns in.
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	cat.display_name = "Whiskers, Rescued"
	inv.give_quest_item(cat)
	town._on_board_entry_selected(lost_cat)
	_check(not inv.has_quest_item(&"rescued_cat"), "turning in consumes the rescued_cat item")
	_check(inv.has_completed_quest(&"lost_cat"), "turning in completes the quest")
	_check(inv.has_quest_item(&"thank_you_note"), "turning in grants the Thank You Note")

	# Click a completed quest again: no-op.
	var before_size: int = inv.quest_items.size()
	entries = town._make_quest_entries()
	for e: QuestBoardEntry in entries:
		if e.id == &"lost_cat":
			lost_cat = e
	_check(lost_cat.category == QuestBoardEntry.Category.RECAP, "Lost Cat becomes RECAP once completed")
	town._on_board_entry_selected(lost_cat)
	_check(inv.quest_items.size() == before_size, "clicking a completed quest again grants nothing extra")

	# The other 2 placeholder entries (empty id) are always no-ops.
	var placeholder := QuestBoardEntry.new()
	placeholder.id = &""
	var accepted_before: int = inv.accepted_quest_ids.size()
	town._on_board_entry_selected(placeholder)
	_check(inv.accepted_quest_ids.size() == accepted_before, "clicking a placeholder (empty id) entry does nothing")

	_instance.free()
	print(("LOST CAT BOARD FLOW TEST PASSED" if _failures == 0 else "LOST CAT BOARD FLOW TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_board_flow.gd`
Expected: FAIL — `_on_board_entry_selected` doesn't exist yet; `_make_quest_entries()` doesn't
state-branch yet.

- [ ] **Step 3: Confirmed `world/town_demo.gd`'s `class_name` is `TownDemo`**

(Already verified during this plan's research — `world/town_demo.gd:1` declares `class_name TownDemo
extends Node2D`. The test above already uses `TownDemo`. No action needed for this step beyond
awareness; it's listed so the implementer isn't surprised the type isn't called `Town`.)

- [ ] **Step 4: Update `_make_quest_entries()` in `world/town_demo.gd`**

Change:
```gdscript
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
```
to:
```gdscript
func _make_quest_entries() -> Array[QuestBoardEntry]:
	var lost_cat_body: String
	var lost_cat_category: QuestBoardEntry.Category
	if _party_inventory.has_completed_quest(&"lost_cat"):
		lost_cat_body = "Whiskers is home safe, thanks to you."
		lost_cat_category = QuestBoardEntry.Category.RECAP
	elif _party_inventory.has_accepted_quest(&"lost_cat"):
		lost_cat_body = "Bring the rescued cat back here to complete the quest."
		lost_cat_category = QuestBoardEntry.Category.CURRENT
	else:
		lost_cat_body = "A cat's gone missing — last seen near the old dungeon entrance. Whoever finds it should bring it back here."
		lost_cat_category = QuestBoardEntry.Category.SIDE
	var raw: Array[Dictionary] = [
		{"title": "Clear the Cellar", "category": QuestBoardEntry.Category.CURRENT, "body": "Coming soon.", "id": &""},
		{"title": "Lost Cat", "category": lost_cat_category, "body": lost_cat_body, "id": &"lost_cat"},
		{"title": "How We Got Here", "category": QuestBoardEntry.Category.RECAP, "body": "Coming soon.", "id": &""},
	]
	var entries: Array[QuestBoardEntry] = []
	for data in raw:
		var entry := QuestBoardEntry.new()
		entry.title = data["title"]
		entry.category = data["category"]
		entry.body_text = data["body"]
		entry.id = data["id"]
		entries.append(entry)
	return entries
```

- [ ] **Step 5: Wire `entry_selected` and add the handler**

Find where `_board_panel = AdventuringBoardPanel.new()` is constructed in `world/town_demo.gd` and
add, immediately after:
```gdscript
	_board_panel.entry_selected.connect(_on_board_entry_selected)
```
Add this new method (anywhere in the file's function section — near `_on_party_selection_pressed()`
is a reasonable spot):
```gdscript
func _on_board_entry_selected(entry: QuestBoardEntry) -> void:
	if entry.id == &"":
		return
	if not _party_inventory.has_accepted_quest(entry.id):
		_party_inventory.accept_quest(entry.id)
		_board_panel.open_for(_make_quest_entries())
		return
	if _party_inventory.has_completed_quest(entry.id):
		return
	if entry.id == &"lost_cat" and _party_inventory.has_quest_item(&"rescued_cat"):
		_party_inventory.consume_quest_item(&"rescued_cat")
		_party_inventory.complete_quest(&"lost_cat")
		_party_inventory.give_quest_item(_make_thank_you_note())
		_board_panel.open_for(_make_quest_entries())
```
Add this new helper (near `_on_board_entry_selected`):
```gdscript
func _make_thank_you_note() -> QuestItem:
	var note := QuestItem.new()
	note.item_id = &"thank_you_note"
	note.display_name = "A Thank You Note"
	return note
```

- [ ] **Step 6: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 7: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_board_flow.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 8: Run existing board/town regression tests**

Locate and run the existing test(s) covering `AdventuringBoardPanel`/the board's Party Selection flow
(e.g. `tests/test_adventuring_board_panel.gd` — **note**: this file has a known, pre-existing,
unrelated failure documented in `CLAUDE.md` since 2026-07-14; confirm it's still the SAME failure, not
a new one, and do not attempt to fix it here) and any general town-demo smoke test. Confirm no NEW
regressions.

- [ ] **Step 9: Commit**

```bash
git add world/town_demo.gd tests/test_lost_cat_board_flow.gd
git commit -m "feat(world): wire the Adventuring Board's accept/track/turn-in flow for Lost Cat"
```

---

### Task 4: The caged cat — floor 4 placement

**Files:**
- Create: `world/caged_cat.gd`
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_caged_cat.gd` (new)

**Interfaces:**
- Consumes: `Interactable` (base class), `PartyInventory.give_quest_item` (pre-existing),
  `CombatHandoff.is_defeated`/`mark_defeated` (pre-existing).
- Produces: `CagedCat` class; `DungeonDemo._place_caged_cat()`; `DungeonDemo.show_message(text: String)`.
- Consumed by: nothing further in this plan (leaf feature) — exercised end-to-end by Task 7.

- [ ] **Step 1: Write the failing test**

Create `tests/test_caged_cat.gd`:

```gdscript
extends SceneTree

## Headless test for CagedCat (spec 2026-07-19 §3.4): pre-boss-defeat interact shows a locked
## message and grants nothing; post-defeat interact grants rescued_cat exactly once and frees itself.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()

	# Pre-defeat: locked, grants nothing.
	var cat_locked := CagedCat.new()
	cat_locked.party_inventory = inv
	cat_locked.boss_defeated = false
	var message_received: String = ""
	cat_locked.locked_message_requested.connect(func(text: String) -> void: message_received = text)
	cat_locked.interact()
	_check(message_received != "", "interacting before the boss is defeated shows a locked message")
	_check(not inv.has_quest_item(&"rescued_cat"), "no quest item granted before the boss is defeated")
	_check(is_instance_valid(cat_locked), "the cat does NOT free itself before the boss is defeated")
	cat_locked.free()

	# Post-defeat: grants the item, frees itself.
	var cat_rescued := CagedCat.new()
	cat_rescued.party_inventory = inv
	cat_rescued.boss_defeated = true
	var rescued_fired: bool = false
	cat_rescued.cat_rescued.connect(func() -> void: rescued_fired = true)
	cat_rescued.interact()
	_check(inv.has_quest_item(&"rescued_cat"), "interacting after the boss is defeated grants rescued_cat")
	_check(rescued_fired, "cat_rescued signal fires on a successful rescue")

	print(("CAGED CAT TEST PASSED" if _failures == 0 else "CAGED CAT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_caged_cat.gd`
Expected: FAIL — `CagedCat` doesn't exist yet.

- [ ] **Step 3: Create `world/caged_cat.gd`**

```gdscript
class_name CagedCat
extends Interactable

## Floor 4's caged cat, "Whiskers" (spec 2026-07-19). Built fresh every scene load (like every other
## dungeon placement) — its INTERACT behavior branches on whether the Hollow Warden encounter is
## already marked defeated, checked by the driving scene at construction time (matching the existing
## defeated/no-respawn convention: dungeon_demo.gd decides what to build, this class doesn't reach
## into CombatHandoff itself). Pre-rescue: a flavor "still caged" message, grants nothing. Post-rescue:
## grants the "Rescued Cat" QuestItem once, then frees itself (mirrors GroundItemPickup's one-shot
## collect-then-vanish shape).

signal cat_rescued
signal locked_message_requested(text: String)

var party_inventory: PartyInventory
var boss_defeated: bool = false

func _init() -> void:
	prompt_text = "Free the cat"

func interact() -> void:
	if not boss_defeated:
		locked_message_requested.emit("The cage is still locked — something guards it.")
		return
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	cat.display_name = "Whiskers, Rescued"
	party_inventory.give_quest_item(cat)
	cat_rescued.emit()
	queue_free()
```

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_caged_cat.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Place the cat on floor 4 in `world/dungeon_demo.gd`**

Add a new constant near the existing `ENEMY_LOCAL`/`KEY_LOCAL` constants:
```gdscript
const CAT_LOCAL := Vector2(650, 200)   # floor 4 (index 3); clear of its StairsUp (100,500) and enemy (400,300)
```
Add a new general-purpose notification method, alongside the existing `show_locked_message()`/
`show_unlocked_message()`:
```gdscript
## A general-purpose notification, alongside the existing fixed-text show_locked_message()/
## show_unlocked_message() (both about the dungeon-key gate specifically). Reuses the same
## _pickup_debug_label the scene already shows one-off notifications in.
func show_message(text: String) -> void:
	_pickup_debug_label.text = text
```
Add a new placement method:
```gdscript
func _place_caged_cat() -> void:
	if _handoff().is_defeated(&"WhiskersPickup"):
		return
	var cat := CagedCat.new()
	cat.name = "WhiskersPickup"
	cat.party_inventory = _party_inventory
	cat.boss_defeated = _handoff().is_defeated(&"DungeonFloor4Enemy")
	cat.global_position = floor_bounds(3).position + CAT_LOCAL
	cat.locked_message_requested.connect(show_message)
	cat.cat_rescued.connect(func() -> void: _handoff().mark_defeated(&"WhiskersPickup"))
	_floors[3].add_child(cat)
```
Call it once, alongside the existing `_place_dungeon_key()` call (search for where that's invoked in
the scene's build sequence) — add `_place_caged_cat()` right after it.

- [ ] **Step 7: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 8: Extend `tests/test_dungeon_demo_scene.gd` for the cat's placement**

Read the existing test file, then add assertions confirming: floor 4 (`_floors[3]`) has a node named
`WhiskersPickup`; that node is a `CagedCat`; its `boss_defeated` matches
`_handoff().is_defeated(&"DungeonFloor4Enemy")` at scene-build time (should be `false` on a fresh,
undefeated-boss scenario); its `party_inventory` is wired to the scene's live `_party_inventory`.

- [ ] **Step 9: Run the extended dungeon scene test**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd`
Expected: exit code 0.

- [ ] **Step 10: Write a no-respawn regression test**

Create `tests/test_whiskers_no_respawn.gd`, mirroring the established `RewardPickup`/`GatheringNode`
no-respawn-on-rebuild pattern (find one of those existing tests for the exact real-sequence
technique — mark `&"WhiskersPickup"` defeated via `CombatHandoff.mark_defeated()`, rebuild the dungeon
scene fresh, confirm `_floors[3].get_node_or_null("WhiskersPickup")` is `null` this time). Use the
`_failures`/`quit(_failures)` pattern. Run it, confirm exit code 0.

- [ ] **Step 11: Commit**

```bash
git add world/caged_cat.gd world/dungeon_demo.gd tests/test_caged_cat.gd tests/test_dungeon_demo_scene.gd tests/test_whiskers_no_respawn.gd
git commit -m "feat(world): add the caged cat (Whiskers) to dungeon floor 4"
```

---

### Task 5: On-screen quest tracker

**Files:**
- Create: `world/ui/quest_tracker_panel.gd`
- Modify: `world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd`
- Test: `tests/test_quest_tracker_panel.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.has_accepted_quest`/`has_completed_quest`/`has_quest_item` (Task 1 +
  pre-existing).
- Produces: `QuestTrackerPanel.refresh(party_inventory: PartyInventory) -> void`.
- Consumed by: nothing further in this plan — a leaf UI feature, exercised end-to-end by Task 7.

- [ ] **Step 1: Write the failing test**

Create `tests/test_quest_tracker_panel.gd`:

```gdscript
extends SceneTree

## Headless test for QuestTrackerPanel (spec 2026-07-19 §3.5): hidden when the Lost Cat quest isn't
## accepted; shows the "rescue" objective once accepted; shows the "bring it back" objective once the
## player holds the rescued cat; hidden again once completed.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()
	var tracker := QuestTrackerPanel.new()

	tracker.refresh(inv)
	_check(not tracker.visible, "hidden when the quest isn't accepted")

	inv.accept_quest(&"lost_cat")
	tracker.refresh(inv)
	_check(tracker.visible, "visible once accepted")
	_check(tracker.text.to_lower().contains("rescue"), "shows the rescue objective before holding the cat (got: %s)" % tracker.text)

	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	inv.give_quest_item(cat)
	tracker.refresh(inv)
	_check(tracker.text.to_lower().contains("bring"), "shows the bring-it-back objective once holding the cat (got: %s)" % tracker.text)

	inv.consume_quest_item(&"rescued_cat")
	inv.complete_quest(&"lost_cat")
	tracker.refresh(inv)
	_check(not tracker.visible, "hidden again once completed")

	tracker.free()
	print(("QUEST TRACKER PANEL TEST PASSED" if _failures == 0 else "QUEST TRACKER PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_tracker_panel.gd`
Expected: FAIL — `QuestTrackerPanel` doesn't exist yet.

- [ ] **Step 3: Create `world/ui/quest_tracker_panel.gd`**

```gdscript
class_name QuestTrackerPanel
extends Label

## On-screen quest tracker (spec 2026-07-19), same placement/refresh convention as the Amber HUD.
## Shows the current accepted-but-not-completed quest's title + one-line objective; hidden entirely
## when none is active. Sized for exactly one quest today, generic enough to extend later.

func refresh(party_inventory: PartyInventory) -> void:
	if party_inventory.has_accepted_quest(&"lost_cat") and not party_inventory.has_completed_quest(&"lost_cat"):
		text = "Lost Cat\n%s" % _lost_cat_objective(party_inventory)
		show()
	else:
		hide()

## The Lost Cat quest's one-line objective, reflecting real progress — kept alongside the board's own
## _make_quest_entries() state branching (town_demo.gd) so the two texts don't drift out of sync.
static func _lost_cat_objective(party_inventory: PartyInventory) -> String:
	if party_inventory.has_quest_item(&"rescued_cat"):
		return "Bring Whiskers back to the Adventuring Board."
	return "Rescue the cat from the dungeon."
```

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_tracker_panel.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Wire into `world/town_demo.gd`**

Find where `_amber_label` is constructed (search for `_amber_label = Label.new()`) and add,
immediately after, a new field `var _quest_tracker: QuestTrackerPanel` (declared near the existing
`var _amber_label: Label`) and its construction:
```gdscript
	_quest_tracker = QuestTrackerPanel.new()
	_quest_tracker.position = Vector2(16, 140)
	_ui_layer.add_child(_quest_tracker)
```
Find the existing `_amber_label.text = "Amber: %d" % _party_inventory.amber` line (inside
`_process()`) and add, immediately after:
```gdscript
	_quest_tracker.refresh(_party_inventory)
```

- [ ] **Step 7: Wire into `world/overworld_demo.gd`** (`class_name OverworldDemo`)

Confirmed during this plan's research: `_amber_label` is built inline inside a UI-building function
that has a local `ui` node parameter/variable (NOT a stored `_ui_layer` field like `town_demo.gd`
has) — the exact block reads:
```gdscript
	_amber_label = Label.new()
	_amber_label.name = "AmberLabel"
	_amber_label.position = Vector2(16, 100)
	_amber_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	ui.add_child(_amber_label)
```
Add a new field `var _quest_tracker: QuestTrackerPanel` near the existing `var _amber_label: Label`,
and immediately after the block above (still inside the same function, so `ui` is in scope):
```gdscript
	_quest_tracker = QuestTrackerPanel.new()
	_quest_tracker.position = Vector2(16, 140)
	ui.add_child(_quest_tracker)
```
Find this scene's `_process()` update of `_amber_label.text = "Amber: %d" % _party_inventory.amber`
and add, immediately after:
```gdscript
	_quest_tracker.refresh(_party_inventory)
```

- [ ] **Step 8: Wire into `world/dungeon_demo.gd`** (`class_name DungeonDemo`)

Same pattern as Step 7 — confirmed this scene ALSO builds `_amber_label` via a local `ui` node
(`ui.add_child(_amber_label)`), not a stored `_ui_layer` field. Apply the identical
field-declaration + construction (`ui.add_child(_quest_tracker)`) + `_process()`-refresh pattern.

- [ ] **Step 9: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 10: Manually smoke-test all 3 scenes load without error**

Run each of these and confirm exit code 0 with no SCRIPT ERROR lines (these are full-scene smoke
tests, not test files — use the existing scene-smoke test files if present, e.g.
`tests/test_scene_party_smoke.gd`, or run the existing scene-level test for each of
town/overworld/dungeon):
```
../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd
```
(and equivalents for town/overworld if such scene-smoke tests exist — search `tests/` for coverage).

- [ ] **Step 11: Commit**

```bash
git add world/ui/quest_tracker_panel.gd world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_quest_tracker_panel.gd
git commit -m "feat(world-ui): add the on-screen Lost Cat quest tracker"
```

---

### Task 6: The Thank You Note — Quest Items tab interactivity

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Modify: `world/town_demo.gd`
- Test: `tests/test_thank_you_note_dialogue.gd` (new)

**Interfaces:**
- Consumes: `InventoryMenuPanel._pc`/`_companions` (pre-existing fields, already set by `open_for()`),
  `DialogueBox.open(dialogue_set: DialogueSet)` (pre-existing).
- Produces: `InventoryMenuPanel.thank_you_note_requested(dialogue_set: DialogueSet)` signal; Quest
  Items tab rows become clickable `Button`s.
- Consumed by: nothing further in this plan — exercised end-to-end by Task 7.

- [ ] **Step 1: Write the failing test**

Create `tests/test_thank_you_note_dialogue.gd`:

```gdscript
extends SceneTree

## Headless test for the Thank You Note's dialogue interactivity (spec 2026-07-19 §3.6): clicking its
## Quest Items tab row opens a DialogueSet naming the CURRENT live party (PC + companions), read at
## click time, not baked in at grant time; clicking any OTHER quest item's row does nothing.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel := InventoryMenuPanel.new()

	var pc := Combatant.new()
	pc.display_name = "Martin"
	var companion1 := Combatant.new()
	companion1.display_name = "Basil"
	var inv := PartyInventory.new()
	var note := QuestItem.new()
	note.item_id = &"thank_you_note"
	note.display_name = "A Thank You Note"
	inv.give_quest_item(note)
	var vault := Vault.new()

	panel.open_for(pc, [companion1], inv, vault)

	var received_set: DialogueSet = null
	panel.thank_you_note_requested.connect(func(s: DialogueSet) -> void: received_set = s)
	panel._on_thank_you_note_pressed()
	_check(received_set != null, "pressing the Thank You Note emits thank_you_note_requested")
	_check(received_set.lines.size() == 1, "the dialogue has exactly 1 line")
	_check(received_set.lines[0].text.contains("Martin"), "the dialogue names the PC")
	_check(received_set.lines[0].text.contains("Basil"), "the dialogue names the companion")

	# A party-of-1 (no companions) still works and doesn't crash on an empty companions array.
	var panel2 := InventoryMenuPanel.new()
	panel2.open_for(pc, [], inv, vault)
	var received_set2: DialogueSet = null
	panel2.thank_you_note_requested.connect(func(s: DialogueSet) -> void: received_set2 = s)
	panel2._on_thank_you_note_pressed()
	_check(received_set2 != null and received_set2.lines[0].text.contains("Martin"), "a party of 1 still produces a real dialogue naming the PC")

	print(("THANK YOU NOTE DIALOGUE TEST PASSED" if _failures == 0 else "THANK YOU NOTE DIALOGUE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_thank_you_note_dialogue.gd`
Expected: FAIL — `thank_you_note_requested`/`_on_thank_you_note_pressed()` don't exist yet.

- [ ] **Step 3: Give the Quest Items tab Button rows in `combat/ui/inventory_menu_panel.gd`**

Change:
```gdscript
func _build_quest_panel() -> void:
	if _party_inventory.quest_items.is_empty():
		_build_list_empty_message("No quest items yet.")
		return
	for i in range(_party_inventory.quest_items.size()):
		var entry: Resource = _party_inventory.quest_items[i]
		var label_text: String = entry.display_name if entry is QuestItem else "Quest item %d" % (i + 1)
		_build_list_row(i, label_text)
```
to:
```gdscript
func _build_quest_panel() -> void:
	if _party_inventory.quest_items.is_empty():
		_build_list_empty_message("No quest items yet.")
		return
	for i in range(_party_inventory.quest_items.size()):
		var entry: Resource = _party_inventory.quest_items[i]
		var label_text: String = entry.display_name if entry is QuestItem else "Quest item %d" % (i + 1)
		_build_quest_row(i, label_text, entry)

func _build_quest_row(index: int, text: String, entry: Resource) -> void:
	var btn := Button.new()
	btn.text = text
	btn.position = Vector2(PAD, GRID_TOP + float(index) * (SLOT_H + SLOT_GAP))
	btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	if entry is QuestItem and entry.item_id == &"thank_you_note":
		btn.pressed.connect(_on_thank_you_note_pressed)
	add_child(btn)
	_list_labels.append(btn)
```

- [ ] **Step 4: Add the signal and handler**

Add this signal declaration near the top of the file, alongside any other existing signal
declarations:
```gdscript
signal thank_you_note_requested(dialogue_set: DialogueSet)
```
Add this new method (anywhere in the function section, near `_build_quest_row`):
```gdscript
func _on_thank_you_note_pressed() -> void:
	var names: Array[String] = [_pc.display_name]
	for c: Combatant in _companions:
		names.append(c.display_name)
	var line := DialogueLine.new()
	line.speaker_name = "Whiskers' Owner"
	line.text = "Thank you, %s! You saved my little Whiskers." % ", ".join(names)
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = [line]
	thank_you_note_requested.emit(dialogue_set)
```

- [ ] **Step 5: Wire the signal in `world/town_demo.gd`**

Find where `_inventory_panel` is constructed (search for `_inventory_panel = InventoryMenuPanel.new()`)
and add, immediately after:
```gdscript
	_inventory_panel.thank_you_note_requested.connect(_dialogue_box.open)
```

- [ ] **Step 6: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 7: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_thank_you_note_dialogue.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 8: Run existing InventoryMenuPanel regression tests**

Locate and run the existing tests covering `InventoryMenuPanel`'s Quest Items/Materials tabs (search
`tests/` for coverage, e.g. anything asserting on `_build_quest_panel`/`_build_material_row`) —
confirm no regressions (the Materials tab's `Button`-row pattern is untouched; only the Quest tab's
rendering changed from `Label` to `Button`).

- [ ] **Step 9: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd world/town_demo.gd tests/test_thank_you_note_dialogue.gd
git commit -m "feat(combat-ui): make the Thank You Note's Quest Items row open its dialogue"
```

---

### Task 7: Full end-to-end test + regression sweep + status doc

**Files:**
- Create: `tests/test_lost_cat_quest_full_sequence.gd`
- Modify: `CLAUDE.md`

**Interfaces:** none new — integration proof + verification + documentation.

- [ ] **Step 1: Write the full-sequence integration test**

Create `tests/test_lost_cat_quest_full_sequence.gd` — a single scenario proving the WHOLE quest cycle
works together: accept at the board → the cat is locked pre-boss-defeat → mark the boss defeated →
the cat now grants the rescued-cat item → the on-screen tracker reflects each stage → turn in at the
board → the Thank You Note is granted and its dialogue names the live party. Use the
`_failures`/`quit(_failures)` pattern and, if instantiating `town_demo.tscn`/`dungeon_demo.tscn`, type
the scene handle as its real `class_name` (confirmed in Task 3/4), never `Node`. Structure it as a
sequence of direct method calls on the real scene objects and resources (matching this plan's other
integration tests), not a full manual-input simulation:

```gdscript
extends SceneTree

## Full end-to-end integration test for the Lost Cat quest (spec 2026-07-19) — proves every piece
## built across Tasks 1-6 works TOGETHER: accept → locked cat → boss defeated → rescue → tracker
## updates → turn in → Thank You Note.

var _town: TownDemo
var _failures: int = 0

func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_town = scene.instantiate() as TownDemo
	root.add_child(_town)
	await process_frame
	await process_frame

	var inv: PartyInventory = _town._party_inventory
	var tracker := QuestTrackerPanel.new()

	# 1. Not accepted: tracker hidden.
	tracker.refresh(inv)
	_check(not tracker.visible, "tracker hidden before accepting")

	# 2. Accept at the board.
	var entries: Array[QuestBoardEntry] = _town._make_quest_entries()
	var lost_cat: QuestBoardEntry = null
	for e: QuestBoardEntry in entries:
		if e.id == &"lost_cat":
			lost_cat = e
	_town._on_board_entry_selected(lost_cat)
	_check(inv.has_accepted_quest(&"lost_cat"), "accepted for real via the board handler")
	tracker.refresh(inv)
	_check(tracker.text.to_lower().contains("rescue"), "tracker shows the rescue objective")

	# 3. The cat is locked before the boss is defeated.
	var cat := CagedCat.new()
	cat.party_inventory = inv
	cat.boss_defeated = false
	var locked_message: String = ""
	cat.locked_message_requested.connect(func(t: String) -> void: locked_message = t)
	cat.interact()
	_check(locked_message != "", "the cat is locked before the boss is defeated")
	_check(not inv.has_quest_item(&"rescued_cat"), "no rescue yet")
	cat.free()

	# 4. Boss defeated — the cat now grants the item.
	var cat2 := CagedCat.new()
	cat2.party_inventory = inv
	cat2.boss_defeated = true
	cat2.interact()
	_check(inv.has_quest_item(&"rescued_cat"), "the cat grants rescued_cat once the boss is defeated")
	tracker.refresh(inv)
	_check(tracker.text.to_lower().contains("bring"), "tracker updates to the bring-it-back objective")

	# 5. Turn in at the board.
	entries = _town._make_quest_entries()
	for e: QuestBoardEntry in entries:
		if e.id == &"lost_cat":
			lost_cat = e
	_town._on_board_entry_selected(lost_cat)
	_check(inv.has_completed_quest(&"lost_cat"), "turned in for real via the board handler")
	_check(inv.has_quest_item(&"thank_you_note"), "the Thank You Note is granted")
	tracker.refresh(inv)
	_check(not tracker.visible, "tracker hides again once completed")

	# 6. The Thank You Note's dialogue names the live party.
	var received_set: DialogueSet = null
	_town._inventory_panel.open_for(_town._pc_combatant, _town._companions, inv, _town._vault)
	_town._inventory_panel.thank_you_note_requested.connect(func(s: DialogueSet) -> void: received_set = s)
	_town._inventory_panel._on_thank_you_note_pressed()
	_check(received_set != null and received_set.lines[0].text.contains(_town._pc_combatant.display_name), "the Thank You Note names the real live PC")

	tracker.free()
	_town.free()
	print(("LOST CAT QUEST FULL SEQUENCE TEST PASSED" if _failures == 0 else "LOST CAT QUEST FULL SEQUENCE TEST FAILED: %d" % _failures))
	quit(_failures)
```

(Already verified during this plan's research: `TownDemo` declares `_pc_combatant: Combatant`
(line 36), `_companions: Array[Combatant]` (line 37), `_vault: Vault` (line 40), and calls
`_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, true)` at its own
existing call site (line 500) — confirming these are exactly the right field names/types to reuse
above, not a guess.)

- [ ] **Step 2: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_quest_full_sequence.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 3: Full headless suite regression sweep**

```bash
for f in tests/test_*.gd; do
  name=$(basename "$f")
  ../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script "res://tests/$name" > /dev/null 2>&1
  code=$?
  if [ $code -ne 0 ]; then
    echo "NONZERO EXIT ($code): $name"
  fi
done
echo "sweep complete"
```

Retry any nonzero-exit file individually once — this project has a documented intermittent
teardown-only SIGSEGV flake class that clears on retry, and one pre-existing, unrelated failure
(`tests/test_adventuring_board_panel.gd`, documented in `CLAUDE.md` since 2026-07-14). Anything else
that fails consistently on retry is a real regression from this plan's work and must be fixed before
proceeding — do not dismiss it.

- [ ] **Step 4: Update `CLAUDE.md`'s status section**

Add a new entry after the most recent SHIPPED entry (match the existing entries' style/format)
describing: the Lost Cat quest shipped — `PartyInventory` quest-state tracking, the Adventuring
Board's real accept/track/turn-in flow, the caged cat on floor 4 (locked pre-boss-defeat, grants the
rescued-cat item post-defeat), the on-screen quest tracker (Amber-HUD-style), and the Thank You
Note's live-party-naming dialogue. Note this closes out all 3 plans of the dungeon-boss + Lost Cat
feature (spec `docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md`). Note
that a human has not yet playtested this live — that's the next step.

- [ ] **Step 5: Commit**

```bash
git add tests/test_lost_cat_quest_full_sequence.gd CLAUDE.md
git commit -m "test(world): full Lost Cat quest sequence + record shipped status"
```
