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
