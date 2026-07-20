extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var entry := QuestBoardEntry.new()
	_check(entry.category == QuestBoardEntry.Category.CURRENT, "category defaults to CURRENT")
	entry.title = "Clear the Cellar"
	entry.category = QuestBoardEntry.Category.SIDE
	entry.body_text = "Coming soon."
	_check(entry.title == "Clear the Cellar", "title settable")
	_check(entry.category == QuestBoardEntry.Category.SIDE, "category settable")
	_check(entry.body_text == "Coming soon.", "body_text settable")
	_check(entry.id == &"", "QuestBoardEntry.id defaults to empty StringName (got %s)" % entry.id)
	entry.id = &"lost_cat"
	_check(entry.id == &"lost_cat", "QuestBoardEntry.id can be set to a real quest id")
	quit()
