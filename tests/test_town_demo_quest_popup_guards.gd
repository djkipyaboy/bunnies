# tests/test_town_demo_quest_popup_guards.gd
extends SceneTree

## Headless test for the final-review fix (2026-08-10, Finding 1): QuestPopupPanel used to sit in
## ZERO mutual-exclusion guard chains in town_demo.gd — it never paused/resumed PC movement, had no
## `declined` handler at all, was absent from every other panel's open-guard, and pressing 'E' while
## it was open (opened from a board row click, so it renders ON TOP of the Board) could close the
## Board out from under it, unpausing movement and leaving the popup stuck on screen while every
## other panel's guard was satisfied. This covers: movement pause/resume across open->accept and
## open->decline, the popup blocking _toggle_professions(), and 'E' NOT closing the Board while the
## popup is showing.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	var town: TownDemo = scene.instantiate() as TownDemo
	root.add_child(town)
	await process_frame
	await process_frame

	var inv: PartyInventory = town._party_inventory

	# Open the Board, then click the unaccepted Lost Cat row — this opens the popup ON TOP of the
	# (still-open) Board, mirroring the real _on_board_entry_selected() -> open_offer() path.
	var empty_entries: Array[QuestBoardEntry] = []
	town._on_board_opened(empty_entries)
	_check(town._board_panel.is_open(), "the Board is open")
	_check(town._pc.movement_paused_for_test(), "opening the Board pauses movement")

	var entries: Array[QuestBoardEntry] = town._make_quest_entries()
	var lost_cat: QuestBoardEntry = null
	for e: QuestBoardEntry in entries:
		if e.id == &"lost_cat":
			lost_cat = e
	_check(lost_cat != null, "found the Lost Cat board entry")

	town._on_board_entry_selected(lost_cat)
	_check(town._quest_popup_panel.is_open(), "clicking the unaccepted row opens the popup")
	_check(town._pc.movement_paused_for_test(), "movement stays paused while the popup is open")

	# Every other modal panel's guard must refuse to open while the popup is up.
	town._toggle_professions()
	_check(not town._professions_panel.is_open(), "the popup blocks _toggle_professions() from opening Professions")
	town._toggle_inventory()
	_check(not town._inventory_panel.visible, "the popup blocks _toggle_inventory() from opening Inventory")
	town._toggle_talents()
	_check(not town._talent_panel.visible, "the popup blocks _toggle_talents() from opening Talents")
	town._toggle_quest_log()
	_check(not town._quest_log_panel.is_open(), "the popup blocks _toggle_quest_log() from opening the Quest Log")
	town._toggle_legend()
	_check(not town._legend_panel.is_open(), "the popup blocks _toggle_legend() from opening the Legend")

	# 'E' (the "interact" action) must NOT close the Board while the popup is showing on top of it —
	# synthesize the same InputEventAction test_town_demo_inventory.gd's own board-close coverage
	# uses, and confirm _unhandled_input()'s early-return keeps the Board open + paused instead of
	# falling through to the Board-close branch.
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	town._unhandled_input(interact_event)
	_check(town._quest_popup_panel.is_open(), "the popup is still open after an 'E' press")
	_check(town._board_panel.is_open(), "the Board is still open after an 'E' press (it would have closed pre-fix)")
	_check(town._pc.movement_paused_for_test(), "movement is still paused after an 'E' press (it would have unpaused pre-fix)")

	# Accept via the popup: movement stays paused (the Board re-opens behind it), and the Board's
	# quest-entry state actually updated.
	town._quest_popup_panel.press_primary_for_test()
	_check(inv.has_accepted_quest(&"lost_cat"), "pressing Accept accepted the quest")
	_check(town._pc.movement_paused_for_test(), "movement stays paused after Accept (the Board re-opened)")
	_check(not town._quest_popup_panel.is_open(), "the popup closed after Accept")

	# Now exercise Decline on a fresh offer — Lost Cat is already accepted, so re-use the tutorial
	# quest's offer path isn't available; instead re-open the popup directly (mirrors how
	# _on_board_entry_selected() would for any not-yet-accepted quest) and confirm Decline resumes
	# movement with no board re-render needed.
	var tutorial_quest: Quest = QuestLibrary.get_quest(&"tutorial")
	town._pc.set_movement_paused(true)
	town._quest_popup_panel.open_offer(tutorial_quest)
	_check(town._quest_popup_panel.is_open(), "re-opened the popup for the Decline check")
	town._quest_popup_panel.press_secondary_for_test()
	_check(not town._quest_popup_panel.is_open(), "the popup closed after Decline")
	_check(not town._pc.movement_paused_for_test(), "declining resumes movement")

	town.free()
	print(("TOWN DEMO QUEST POPUP GUARDS TEST PASSED" if _failures == 0 else "TOWN DEMO QUEST POPUP GUARDS TEST FAILED: %d" % _failures))
	quit(_failures)
