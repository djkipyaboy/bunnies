class_name InventoryDemoSetup
extends RefCounted

## Seeds a hardcoded PC + companion Combatant, a shared PartyInventory, and a Vault with placeholder
## Gear/Weapon instances for the equipment/inventory/banking UI demo (spec
## 2026-07-10-equipment-inventory-banking-ui-design.md §4). NOT the real character-creation or
## companion-recruitment systems (neither exists in code yet) — placeholder data only, split out of
## town_demo.gd per the spec's §6 file-size note. All numeric magnitudes are [ASSUMPTION].

static func seed_demo_party() -> Dictionary:
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.display_name = "Martin"
	pc.level = 9   # can equip every rarity tier, so the demo can show the full ladder

	var companion: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	companion.display_name = "Basil"
	companion.level = 3   # can equip Common/Uncommon only — exercises a visible level-gate rejection

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	vault.tab_capacity[&"gear"] = 10
	vault.tab_capacity[&"weapons"] = 5
	vault.tab_capacity[&"materials"] = 10

	var common_hat: Gear = _make_gear("Cloth Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0, 0, 1, 0, 0, 0))
	var common_chest: Gear = _make_gear("Padded Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, _stats(0, 0, 2, 0, 0, 0))
	var uncommon_cloak: Gear = _make_gear("Traveler's Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.UNCOMMON, _stats(0, 1, 0, 0, 0, 1))
	var rare_gauntlets: Gear = _make_gear_with_affix("Warded Gauntlets", Gear.Slot.HANDS, RarityVisuals.Rarity.RARE, _stats(2, 0, 0, 0, 0, 0))
	var epic_charm: Gear = _make_gear_with_affix("Glowing Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0, 0, 2, 1, 0, 0))
	var spare_sword: Weapon = _make_weapon("Spare Shortsword", 6.0, RarityVisuals.Rarity.COMMON)

	# Pre-equip a couple of items so unequip is testable immediately, not just equip-into-empty.
	pc.gear = [common_hat]
	companion.gear = [common_chest]

	inv.gear = [uncommon_cloak, rare_gauntlets, epic_charm]
	inv.weapons = [spare_sword]

	return {
		"pc": pc,
		"companions": [companion],
		"party_inventory": inv,
		"vault": vault,
	}

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func _make_gear(display_name: String, slot: int, rarity: int, stats: Stats) -> Gear:
	var g: Gear = Gear.new()
	g.display_name = display_name
	g.slot = slot
	g.rarity = rarity
	g.stat_bonuses = stats
	return g

static func _make_gear_with_affix(display_name: String, slot: int, rarity: int, stats: Stats) -> Gear:
	var g: Gear = _make_gear(display_name, slot, rarity, stats)
	g.reel_affixes = [ReelAffix.new()]
	return g

static func _make_weapon(display_name: String, base_damage: float, rarity: int) -> Weapon:
	var w: Weapon = Weapon.new()
	w.display_name = display_name
	w.base_damage = base_damage
	w.rarity = rarity
	return w
