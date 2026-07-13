class_name LootTableLibrary
extends RefCounted

## Code registry of authored LootTables (2026-07-12 combat loot drops spec) — mirrors
## ClassLibrary/EnemyLibrary/EncounterLibrary: returns a FRESH LootTable each call. One authored
## table for this pass: overworld_trash, shared by rat/ferret/stoat (EnemyLibrary wires it in
## Task 3) — one shared table rather than per-enemy tables, per player direction. Common/Uncommon
## Gear only, no weapons this pass. All names/stats/drop_chances are [ASSUMPTION] — tune by
## playtest, not balanced now.

const IDS: Array[StringName] = [&"overworld_trash"]

static func make(id: StringName) -> LootTable:
	match id:
		&"overworld_trash":
			var t: LootTable = LootTable.new()
			t.entries = [
				_entry(_make_gear("Rat-Chewed Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0, 0, 1, 0, 0, 0)), 0.25),
				_entry(_make_gear("Scavenged Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.COMMON, _stats(0, 1, 0, 0, 0, 0)), 0.20),
				_entry(_make_gear("Salvaged Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0, 0, 0, 0, 0, 1)), 0.15),
			]
			return t
		_:
			return null

static func _entry(item: Gear, drop_chance: float) -> LootEntry:
	var e: LootEntry = LootEntry.new()
	e.item = item
	e.drop_chance = drop_chance
	return e

static func _make_gear(display_name: String, slot: int, rarity: int, stats: Stats) -> Gear:
	var g: Gear = Gear.new()
	g.display_name = display_name
	g.slot = slot
	g.rarity = rarity
	g.stat_bonuses = stats
	return g

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s
