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
