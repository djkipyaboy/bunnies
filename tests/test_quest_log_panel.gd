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
