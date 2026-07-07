extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_two_line_set() -> DialogueSet:
	var first := DialogueLine.new()
	first.speaker_name = "Villager"
	first.text = "Hello!"
	var second := DialogueLine.new()
	second.speaker_name = "Villager"
	second.text = "Goodbye!"
	var lines: Array[DialogueLine] = [first, second]
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	return dialogue_set

func _init() -> void:
	var dialogue_set := _make_two_line_set()

	# Pure static logic first — no node/tree involved.
	_check(not DialogueBox.is_finished(dialogue_set, 0), "index 0 is not finished (2-line set)")
	_check(not DialogueBox.is_finished(dialogue_set, 1), "index 1 is not finished (2-line set)")
	_check(DialogueBox.is_finished(dialogue_set, 2), "index 2 IS finished (2-line set)")
	_check(DialogueBox.line_at(dialogue_set, 0).text == "Hello!", "line_at(0) returns the first line")
	_check(DialogueBox.line_at(dialogue_set, 1).text == "Goodbye!", "line_at(1) returns the second line")

	# Instance behavior — built via .new(), never added to a live tree (matches
	# AbilityMenuPanel's test convention: construction logic lives in open(), not _ready()).
	var box := DialogueBox.new()
	_check(not box.is_open(), "DialogueBox starts closed")

	box.open(dialogue_set)
	_check(box.is_open(), "open() shows the box")
	_check(box.current_speaker_for_test() == "Villager", "open() renders the first line's speaker")
	_check(box.current_text_for_test() == "Hello!", "open() renders the first line's text")

	box.advance_for_test()
	_check(box.is_open(), "advancing to the last line keeps the box open")
	_check(box.current_text_for_test() == "Goodbye!", "advance() renders the second line's text")

	# NOTE: GDScript lambdas capture primitives BY VALUE, so a plain `var closed_fired: bool`
	# assigned inside the lambda would never propagate out (verified on 4.6.3). Route the
	# flag through an array element instead — the standard GDScript capture workaround.
	var closed_fired: Array[bool] = [false]
	box.closed.connect(func() -> void: closed_fired[0] = true)
	box.advance_for_test()
	_check(not box.is_open(), "advancing past the last line closes the box")
	_check(closed_fired[0], "closing emits the closed signal")

	box.free()  # never entered the tree, so free manually (matches test_ability_menu_panel.gd)
	quit()
