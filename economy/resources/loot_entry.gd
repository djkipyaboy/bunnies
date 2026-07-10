class_name LootEntry
extends Resource

## One line of a LootTable: an item and its OWN independent drop chance (spec §4.3).

@export var item: Resource
@export var drop_chance: float = 0.0   # 0.0-1.0, rolled independently of every other entry
