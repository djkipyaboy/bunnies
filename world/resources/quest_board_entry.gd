class_name QuestBoardEntry
extends Resource

## One row on the town's Adventuring Board (spec §7). Every row in the 2026-07-07 demo is a
## blank placeholder — no real quest content or tracking exists yet.

enum Category { CURRENT, SIDE, RECAP }

@export var title: String = ""
@export var category: Category = Category.CURRENT
@export var body_text: String = ""
@export var id: StringName = &""
