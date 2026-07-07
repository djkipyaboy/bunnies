extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var line := DialogueLine.new()
	line.speaker_name = "Villager"
	line.text = "Hello there!"
	_check(line.speaker_name == "Villager", "DialogueLine.speaker_name settable")
	_check(line.text == "Hello there!", "DialogueLine.text settable")

	var farewell := DialogueLine.new()
	farewell.speaker_name = "Villager"
	farewell.text = "Safe travels!"

	var lines: Array[DialogueLine] = [line, farewell]
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	_check(dialogue_set.line_count() == 2, "DialogueSet.line_count reflects assigned lines")
	_check(dialogue_set.lines[0] == line, "DialogueSet.lines preserves order (index 0)")
	_check(dialogue_set.lines[1] == farewell, "DialogueSet.lines preserves order (index 1)")

	var empty_set := DialogueSet.new()
	_check(empty_set.line_count() == 0, "DialogueSet defaults to zero lines")
	quit()
