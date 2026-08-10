class_name Quest
extends Resource

## Quest data (2026-08-10 quest-system-and-tutorial design §3) — authored once per quest in
## QuestLibrary, read by QuestLogPanel/QuestTrackerPanel. Objectives are ordered; PartyInventory
## tracks per-quest completion against each QuestObjective's id.

enum Category { CURRENT, SIDE, TUTORIAL }

@export var id: StringName = &""
@export var title: String = ""
@export var description: String = ""
@export var category: Category = Category.SIDE
@export var objectives: Array[QuestObjective] = []
@export var reward_amber: int = 0   ## [ASSUMPTION] placeholder, not balanced (CLAUDE.md §4)
