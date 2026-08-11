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

	# --- New: auto-complete + reward grant (quest-popups-and-tutorial-wiring plan, Task 1) ---

	var inv4 := PartyInventory.new()
	inv4.accept_quest(&"tutorial")
	var tutorial: Quest = QuestLibrary.get_quest(&"tutorial")
	for i in range(tutorial.objectives.size() - 1):
		inv4.complete_objective(&"tutorial", tutorial.objectives[i].id)
		_check(not inv4.has_completed_quest(&"tutorial"), "tutorial isn't auto-completed until the LAST objective finishes (got objective %d)" % i)
	var amber_before: int = inv4.amber
	inv4.complete_objective(&"tutorial", tutorial.objectives[tutorial.objectives.size() - 1].id)
	_check(inv4.has_completed_quest(&"tutorial"), "completing the last objective auto-completes the quest")
	_check(inv4.amber == amber_before + tutorial.reward_amber, "completing the quest grants its reward_amber (got %d, expected %d)" % [inv4.amber, amber_before + tutorial.reward_amber])

	# Completing an already-complete quest's objective again must not double-grant the reward.
	inv4.complete_objective(&"tutorial", tutorial.objectives[tutorial.objectives.size() - 1].id)
	_check(inv4.amber == amber_before + tutorial.reward_amber, "re-completing the last objective doesn't grant the reward twice (got %d)" % inv4.amber)

	# lost_cat never calls complete_objective(), so this change must be a no-op for its existing flow.
	var inv5 := PartyInventory.new()
	inv5.accept_quest(&"lost_cat")
	var lost_cat_amber_before: int = inv5.amber
	inv5.complete_quest(&"lost_cat")
	_check(inv5.amber == lost_cat_amber_before, "completing lost_cat grants 0 Amber (its reward_amber is 0 — it rewards via a QuestItem instead)")

	# --- New: quest_completed signal (Plan 3 fix — quest completion had no Event Log entry) ---

	var inv6 := PartyInventory.new()
	var completed_ids: Array[StringName] = []
	inv6.quest_completed.connect(func(quest_id: StringName) -> void: completed_ids.append(quest_id))
	inv6.accept_quest(&"lost_cat")
	inv6.complete_quest(&"lost_cat")
	_check(completed_ids == [&"lost_cat"], "complete_quest emits quest_completed with the quest id (got %s)" % [completed_ids])
	inv6.complete_quest(&"lost_cat")
	_check(completed_ids.size() == 1, "re-completing an already-completed quest doesn't re-emit quest_completed (got %d emissions)" % completed_ids.size())

	var inv7 := PartyInventory.new()
	var auto_completed_ids: Array[StringName] = []
	inv7.quest_completed.connect(func(quest_id: StringName) -> void: auto_completed_ids.append(quest_id))
	inv7.accept_quest(&"tutorial")
	var tutorial2: Quest = QuestLibrary.get_quest(&"tutorial")
	for objective: QuestObjective in tutorial2.objectives:
		inv7.complete_objective(&"tutorial", objective.id)
	_check(auto_completed_ids == [&"tutorial"], "auto-completing the tutorial via complete_objective() ALSO emits quest_completed (got %s)" % [auto_completed_ids])

	print(("PARTY INVENTORY QUEST STATE TEST PASSED" if _failures == 0 else "PARTY INVENTORY QUEST STATE TEST FAILED: %d" % _failures))
	quit(_failures)
