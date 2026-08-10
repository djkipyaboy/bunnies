# tests/test_quest_resources.gd
extends SceneTree

## Headless test for the Quest/QuestObjective data resources (2026-08-10 quest-system-and-
## tutorial design §3) — pure data, so this just proves construction and field access work.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var obj := QuestObjective.new()
	obj.id = &"move"
	obj.display_text = "Move around using WASD."
	_check(obj.id == &"move", "QuestObjective.id round-trips")
	_check(obj.display_text == "Move around using WASD.", "QuestObjective.display_text round-trips")

	var quest := Quest.new()
	quest.id = &"tutorial"
	quest.title = "Getting Started"
	quest.description = "Learn the basics before you set out."
	quest.category = Quest.Category.TUTORIAL
	quest.objectives = [obj]
	quest.reward_amber = 25
	_check(quest.category == Quest.Category.TUTORIAL, "Quest.category round-trips")
	_check(quest.objectives.size() == 1, "Quest.objectives holds the appended QuestObjective (got %d)" % quest.objectives.size())
	_check(quest.objectives[0].id == &"move", "the stored objective is the same instance (id matches)")
	_check(quest.category != Quest.Category.CURRENT, "TUTORIAL is distinct from CURRENT")

	print(("QUEST RESOURCES TEST PASSED" if _failures == 0 else "QUEST RESOURCES TEST FAILED: %d" % _failures))
	quit(_failures)
