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
	# NOTE: a lambda connected to a signal captures outer locals BY VALUE in GDScript — assigning to
	# a plain outer var from inside the lambda does not propagate back. Wrap in a 1-element Array
	# (documented gotcha, hit repeatedly across this plan's other tasks) so the mutation is visible.
	var locked_message_box: Array = [""]
	cat.locked_message_requested.connect(func(t: String) -> void: locked_message_box[0] = t)
	cat.interact()
	_check(locked_message_box[0] != "", "the cat is locked before the boss is defeated")
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
	# Same lambda-capture-by-value gotcha as above — wrap in a 1-element Array.
	var received_set_box: Array = [null]
	_town._inventory_panel.open_for(_town._pc_combatant, _town._companions, inv, _town._vault)
	_town._inventory_panel.thank_you_note_requested.connect(func(s: DialogueSet) -> void: received_set_box[0] = s)
	_town._inventory_panel._on_thank_you_note_pressed()
	var received_set: DialogueSet = received_set_box[0]
	_check(received_set != null and received_set.lines[0].text.contains(_town._pc_combatant.display_name), "the Thank You Note names the real live PC")

	tracker.free()
	_town.free()
	print(("LOST CAT QUEST FULL SEQUENCE TEST PASSED" if _failures == 0 else "LOST CAT QUEST FULL SEQUENCE TEST FAILED: %d" % _failures))
	quit(_failures)
