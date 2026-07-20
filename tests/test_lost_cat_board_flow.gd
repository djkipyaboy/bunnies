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
	_instance = scene.instantiate() as TownDemo
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

	# --- Task 3 review-finding coverage: 2 beyond-the-brief fixes in town_demo.gd's board-opening
	# machinery, neither of which the flow above actually exercises. ---

	# Fix #1: _make_quest_entries() guards every _party_inventory read with a null check, because
	# _build_exterior() (which seeds AdventuringBoard's initial `entries` at scene-construction time)
	# runs BEFORE _build_inventory_demo() sets _party_inventory — so the very first call, during a
	# fresh scene's _ready(), happens with _party_inventory still null. By the time THIS test can
	# observe the scene (2 process_frame awaits after add_child), _ready() has already finished, so
	# confirm that ordering genuinely resolved...
	_check(town._party_inventory != null, "_party_inventory is set by the time _make_quest_entries() can be safely called")

	# ...then directly exercise the guard itself: verified by a throwaway repro (instantiate a second
	# TownDemo, null _party_inventory, call _make_quest_entries()) that WITHOUT the null guard this
	# call errors out ("Invalid call. Nonexistent function 'has_completed_quest' in base 'Nil'.") and
	# silently returns an EMPTY array (no Lost Cat row, no rows at all) instead of crashing the whole
	# process — so an empty result is exactly the symptom a reverted guard produces, and is what this
	# assertion must fail on.
	var real_inv: PartyInventory = town._party_inventory
	town._party_inventory = null
	var null_guard_entries: Array[QuestBoardEntry] = town._make_quest_entries()
	town._party_inventory = real_inv
	_check(null_guard_entries.size() == 3, "_make_quest_entries() with a null _party_inventory still returns all 3 rows instead of silently coming back empty")
	var null_guard_lost_cat: QuestBoardEntry = null
	for e: QuestBoardEntry in null_guard_entries:
		if e.id == &"lost_cat":
			null_guard_lost_cat = e
	_check(null_guard_lost_cat != null, "the Lost Cat entry is still present when _party_inventory is null")
	if null_guard_lost_cat != null:
		_check(null_guard_lost_cat.category == QuestBoardEntry.Category.SIDE, "with _party_inventory null, Lost Cat falls back to the not-yet-accepted SIDE state instead of crashing")
		_check(null_guard_lost_cat.body_text.contains("gone missing"), "with _party_inventory null, the fallback body text is the default not-accepted pitch")

	# Fix #2: _on_board_opened() ignores its own `entries` param (AdventuringBoard's `entries` field,
	# frozen once at construction time back in _build_exterior()) and calls
	# _board_panel.open_for(_make_quest_entries()) instead, so a close+reopen always shows the REAL
	# current quest state, not whatever was true the first time the board was ever seeded. By this
	# point in the test the Lost Cat quest is already COMPLETED (RECAP, "Whiskers is home safe..." —
	# asserted above). Build a deliberately STALE entries array — what AdventuringBoard's own frozen
	# `entries` field would still contain if it had never been recomputed since before the quest was
	# even accepted (SIDE, the original not-yet-accepted pitch) — and confirm the panel renders the
	# REAL current (RECAP) state instead of this stale data.
	var stale_lost_cat := QuestBoardEntry.new()
	stale_lost_cat.title = "Lost Cat"
	stale_lost_cat.category = QuestBoardEntry.Category.SIDE
	stale_lost_cat.body_text = "A cat's gone missing — last seen near the old dungeon entrance. Whoever finds it should bring it back here."
	stale_lost_cat.id = &"lost_cat"
	var stale_entries: Array[QuestBoardEntry] = [stale_lost_cat]

	town._on_board_opened(stale_entries)
	var lost_cat_row_index: int = -1
	for i in range(town._board_panel._row_buttons.size()):
		if town._board_panel._row_buttons[i].text == "Lost Cat":
			lost_cat_row_index = i
	_check(lost_cat_row_index != -1, "the Lost Cat row is rendered after _on_board_opened() is called with a stale entries param")
	if lost_cat_row_index != -1:
		town._board_panel.press_row_for_test(lost_cat_row_index)
		_check(town._board_panel._detail_label.text.contains("home safe"), "_on_board_opened() recomputes fresh quest state (RECAP/completed) instead of showing the stale SIDE data passed into its entries param")
		_check(not town._board_panel._detail_label.text.contains("gone missing"), "_on_board_opened() never renders the stale not-yet-accepted pitch text once the quest is actually completed")

	_instance.free()
	print(("LOST CAT BOARD FLOW TEST PASSED" if _failures == 0 else "LOST CAT BOARD FLOW TEST FAILED: %d" % _failures))
	quit(_failures)
