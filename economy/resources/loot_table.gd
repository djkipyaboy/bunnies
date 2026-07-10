class_name LootTable
extends Resource

## WoW-style loot generation: every entry rolls INDEPENDENTLY (spec §4.3) — a kill can drop zero,
## one, or several items, never a single weighted pick. No tables are authored this pass; this
## locks the mechanism only, per the deferred-content direction (loot tables come after more of the
## game's systems exist).

@export var entries: Array[LootEntry] = []

static func roll(table: LootTable) -> Array:
	var drops: Array = []
	for e: LootEntry in table.entries:
		if randf() < e.drop_chance:
			drops.append(e.item)
	return drops
