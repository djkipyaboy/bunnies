# tests/test_quest_library.gd
extends SceneTree

## Headless test for QuestLibrary (2026-08-10 quest-system-and-tutorial design §3).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(QuestLibrary.get_quest(&"nonexistent") == null, "an unknown quest id returns null")

	var lost_cat: Quest = QuestLibrary.get_quest(&"lost_cat")
	_check(lost_cat != null, "lost_cat is registered")
	_check(lost_cat.objectives.size() == 2, "lost_cat has 2 objectives (got %d)" % lost_cat.objectives.size())
	_check(lost_cat.objectives[0].id == &"find_cat", "lost_cat's first objective is 'find_cat'")
	_check(lost_cat.objectives[1].id == &"return_cat", "lost_cat's second objective is 'return_cat'")
	_check(lost_cat.category == Quest.Category.SIDE, "lost_cat is category SIDE")

	var tutorial: Quest = QuestLibrary.get_quest(&"tutorial")
	_check(tutorial != null, "tutorial is registered")
	_check(tutorial.objectives.size() == 10, "tutorial has 10 objectives (got %d)" % tutorial.objectives.size())
	_check(tutorial.category == Quest.Category.TUTORIAL, "tutorial is category TUTORIAL")
	_check(tutorial.objectives[0].id == &"move", "tutorial's first objective is 'move'")
	_check(tutorial.objectives[9].id == &"win_fight", "tutorial's last objective is 'win_fight'")
	_check(tutorial.reward_amber > 0, "tutorial grants a placeholder Amber reward")

	var first_call: Quest = QuestLibrary.get_quest(&"lost_cat")
	var second_call: Quest = QuestLibrary.get_quest(&"lost_cat")
	_check(first_call != second_call, "each call returns a fresh instance, not a shared one (mirrors ShopLibrary's convention)")

	_check(QuestLibrary.all_quests().size() == 2, "all_quests() returns both authored quests")

	print(("QUEST LIBRARY TEST PASSED" if _failures == 0 else "QUEST LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
