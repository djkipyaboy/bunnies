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
