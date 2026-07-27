class_name TreasureTroveLibrary
extends RefCounted

## Code registry of authored dungeon boss rewards (2026-07-27-treasure-trove-and-mountain-entrance-
## design.md §3.1) — mirrors EnemyLibrary/LootTableLibrary's static-registry shape, but deliberately
## NOT a LootTable: every field in the returned bundle is unconditionally granted, no drop_chance
## roll anywhere. Boss rewards stay independent of the random per-kill loot system so a future
## dungeon-difficulty re-challenge system can scale reward rarity per tier without touching that
## system at all. All names/stats/quantities are [ASSUMPTION] — tune by playtest.

const IDS: Array[StringName] = [&"hollow_warden_trove"]

static func make(id: StringName) -> Dictionary:
	match id:
		&"hollow_warden_trove":
			return {
				"gear": _canary_lamp_helm(),
				"amber": 150,
				"material": _wardens_dust(),
				"quest_item": _sunken_sigil(),
			}
		_:
			return {}

static func _canary_lamp_helm() -> Gear:
	var g := Gear.new()
	g.display_name = "Canary Lamp Helm"
	g.slot = Gear.Slot.HEADWEAR
	g.rarity = RarityVisuals.Rarity.RARE
	var s := Stats.new()
	s.vigor = 3
	g.stat_bonuses = s
	return g

static func _wardens_dust() -> CraftingMaterial:
	var m := CraftingMaterial.new()
	m.display_name = "Warden's Dust"
	m.material_type = &"wardens_dust"
	m.quantity = 3
	return m

static func _sunken_sigil() -> QuestItem:
	var q := QuestItem.new()
	q.item_id = &"sunken_sigil"
	q.display_name = "Sunken Sigil"
	q.discardable = false
	q.description = "A cold, sigil-etched stone that hums faintly. Its purpose is unclear. (Story content — not yet implemented.)"
	return q
