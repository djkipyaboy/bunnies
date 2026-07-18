class_name QuestItem
extends Resource

## A key/quest-relevant item that lives in PartyInventory.quest_items (existing since 2026-07-10,
## never populated until now) — uncapped, never banked, visible in the Quest Items tab. First user:
## the dungeon's Rusty Key (2026-07-18 lock-and-key design). item_id is the stable lookup key
## (has_quest_item()/consume_quest_item()); display_name is what the player sees.

@export var display_name: String = ""
@export var item_id: StringName = &""
