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

	## Empty state (final review finding 2): no accepted quests must not leave Track/Abandon
	## live with an empty _selected_quest_id, and both handlers must no-op even if called
	## directly (test hooks bypass the disabled UI state).
	var empty_inv := PartyInventory.new()
	var empty_panel := QuestLogPanel.new()
	empty_panel.open_for(empty_inv)
	_check(empty_panel.detail_text_for_test() == "", "empty Quest Log shows no detail body")
	empty_panel.toggle_track_for_test(true)
	_check(empty_inv.tracked_quest_ids.is_empty(), "toggling Track with no quest selected does not poison tracked_quest_ids")
	empty_panel.press_abandon_for_test()
	_check(empty_inv.accepted_quest_ids.is_empty(), "pressing Abandon with no quest selected is a no-op")
	empty_panel.free()

	print(("QUEST LOG PANEL TEST PASSED" if _failures == 0 else "QUEST LOG PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
