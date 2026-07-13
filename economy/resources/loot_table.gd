class_name LootTable
extends Resource

## WoW-style loot generation: every entry rolls INDEPENDENTLY (spec §4.3) — a kill can drop zero,
## one, or several items, never a single weighted pick.
##
## roll() DUPLICATES each dropped item (2026-07-12 fix) — LootEntry.item is a reusable authored
## template (e.g. LootTableLibrary's shared overworld_trash table rolled across many kills), so
## returning the same Resource reference twice would hand out ALIASED objects: equipping one, or
## even just holding two in a Bag, would silently edit both (Gear/Resource are reference types).
## Deep duplicate (true) so a Gear's own Stats sub-resource isn't shared either.

@export var entries: Array[LootEntry] = []

static func roll(table: LootTable) -> Array:
	var drops: Array = []
	for e: LootEntry in table.entries:
		if e.item != null and randf() < e.drop_chance:
			drops.append(e.item.duplicate(true))
	return drops
