extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var board := AdventuringBoard.new()
	_check(board.prompt_text == "Check the board", "AdventuringBoard sets its own prompt_text")
	_check(board.entries.size() == 0, "entries defaults to an empty array")

	var entry := QuestBoardEntry.new()
	entry.title = "Clear the Cellar"
	var entries: Array[QuestBoardEntry] = [entry]
	board.entries = entries

	# GDScript lambdas capture outer locals BY VALUE — a plain `var received` reassigned
	# inside the lambda would never propagate out. Route it through a one-element array.
	var received_box: Array = [[]]
	board.board_opened.connect(func(opened_entries: Array[QuestBoardEntry]) -> void: received_box[0] = opened_entries)
	board.interact()
	var received: Array = received_box[0]
	_check(received.size() == 1 and received[0] == entry, "interact() emits board_opened with the current entries")
	board.free()  # an Area2D (Node, not RefCounted) never added to a tree — free explicitly
	quit()
