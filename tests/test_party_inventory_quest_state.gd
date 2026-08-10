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

	# --- New in 2026-08-10 quest-system-and-tutorial design §3 ---

	var inv2 := PartyInventory.new()
	_check(inv2.quest_progress.is_empty(), "quest_progress starts empty")
	_check(inv2.tracked_quest_ids.is_empty(), "tracked_quest_ids starts empty")

	inv2.accept_quest(&"tutorial")
	_check(inv2.is_quest_tracked(&"tutorial"), "accepting a quest tracks it by default")

	_check(not inv2.is_objective_complete(&"tutorial", &"move"), "a fresh objective isn't complete")
	var first: QuestObjective = inv2.next_incomplete_objective(&"tutorial")
	_check(first.id == &"move", "next_incomplete_objective returns the first objective in order")

	inv2.complete_objective(&"tutorial", &"move")
	_check(inv2.is_objective_complete(&"tutorial", &"move"), "complete_objective marks it complete")
	var second: QuestObjective = inv2.next_incomplete_objective(&"tutorial")
	_check(second.id == &"open_inventory", "next_incomplete_objective advances once the prior one completes")

	inv2.complete_objective(&"tutorial", &"move")
	_check(inv2.quest_progress[&"tutorial"].size() == 1, "completing the same objective twice doesn't duplicate it (got %d)" % inv2.quest_progress[&"tutorial"].size())

	inv2.set_quest_tracked(&"tutorial", false)
	_check(not inv2.is_quest_tracked(&"tutorial"), "set_quest_tracked(false) untracks")
	_check(inv2.has_accepted_quest(&"tutorial"), "untracking doesn't abandon the quest")

	inv2.abandon_quest(&"tutorial")
	_check(not inv2.has_accepted_quest(&"tutorial"), "abandon_quest removes it from accepted_quest_ids")
	_check(not inv2.is_quest_tracked(&"tutorial"), "abandon_quest also untracks it")

	_check(inv2.next_incomplete_objective(&"nonexistent") == null, "an unknown quest id returns null, not a crash")

	# lost_cat's objectives are special-cased against its existing has_quest_item/has_completed_quest state.
	var inv3 := PartyInventory.new()
	inv3.accept_quest(&"lost_cat")
	_check(inv3.next_incomplete_objective(&"lost_cat").id == &"find_cat", "lost_cat starts on find_cat")
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	inv3.give_quest_item(cat)
	_check(inv3.is_objective_complete(&"lost_cat", &"find_cat"), "find_cat completes once the cat is held")
	_check(inv3.next_incomplete_objective(&"lost_cat").id == &"return_cat", "lost_cat advances to return_cat")
	inv3.consume_quest_item(&"rescued_cat")
	inv3.complete_quest(&"lost_cat")
	_check(inv3.is_objective_complete(&"lost_cat", &"return_cat"), "return_cat completes once the quest is turned in")
	_check(inv3.next_incomplete_objective(&"lost_cat") == null, "lost_cat has no incomplete objectives left")

	print(("PARTY INVENTORY QUEST STATE TEST PASSED" if _failures == 0 else "PARTY INVENTORY QUEST STATE TEST FAILED: %d" % _failures))
	quit(_failures)
