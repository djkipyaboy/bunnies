class_name AdventuringBoard
extends Interactable

## The town's Adventuring Board landmark (spec §7). Every entry in the 2026-07-07 demo is
## a blank placeholder — interact() just hands the current entries to whoever's listening
## (town_demo.gd, which opens AdventuringBoardPanel).

signal board_opened(entries: Array[QuestBoardEntry])

@export var entries: Array[QuestBoardEntry] = []

func _init() -> void:
	prompt_text = "Check the board"

func interact() -> void:
	board_opened.emit(entries)
