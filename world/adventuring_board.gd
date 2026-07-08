class_name AdventuringBoard
extends Interactable

## The town's Adventuring Board landmark (spec §7). Every entry in the 2026-07-07 demo is
## a blank placeholder — interact() just hands the current entries to whoever's listening
## (town_demo.gd, which opens AdventuringBoardPanel).

signal board_opened(entries: Array[QuestBoardEntry])

@export var entries: Array[QuestBoardEntry] = []

func _init() -> void:
	prompt_text = "Check the board"

	var post := ColorRect.new()
	post.color = Color(0.4, 0.28, 0.16)
	post.position = Vector2(-3, -6)
	post.size = Vector2(6, 30)
	add_child(post)

	var board_face := ColorRect.new()
	board_face.color = Color(0.65, 0.5, 0.32)
	board_face.position = Vector2(-14, -26)
	board_face.size = Vector2(28, 22)
	add_child(board_face)

func interact() -> void:
	board_opened.emit(entries)
