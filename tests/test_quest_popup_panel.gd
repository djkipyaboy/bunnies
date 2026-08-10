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
