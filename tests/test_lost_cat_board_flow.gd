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

	_instance.free()
	print(("LOST CAT BOARD FLOW TEST PASSED" if _failures == 0 else "LOST CAT BOARD FLOW TEST FAILED: %d" % _failures))
	quit(_failures)
