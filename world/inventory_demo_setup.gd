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

	# Precreated companion bench (2026-07-12 Party Selection work) — one per remaining class
	# (everything except the PC's own Warrior and the already-in-party Skirmisher/Basil), all at
	# level 3 like Basil — base ability + Ultimate only, no L5/L7/L9 kit, per player direction.
	var bench: Array[Combatant] = []
	for class_id: StringName in ClassLibrary.IDS:
		if class_id == &"warrior" or class_id == &"skirmisher":
			continue
		var recruit: Combatant = ClassLibrary.make(class_id).build_combatant(true)
		recruit.level = 3
		bench.append(recruit)

	var inv: PartyInventory = PartyInventory.new()
	inv.amber = 30   # 2026-07-17 general store design: lets the player buy gear immediately, no combat grind required
	var vault: Vault = Vault.new()
	vault.tab_capacity[&"gear"] = 10
	vault.tab_capacity[&"weapons"] = 5
	vault.tab_capacity[&"materials"] = 10

	var common_hat: Gear = _make_gear("Cloth Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0, 0, 1, 0, 0, 0))
	var common_chest: Gear = _make_gear("Padded Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, _stats(0, 0, 2, 0, 0, 0))
	var uncommon_cloak: Gear = _make_gear("Traveler's Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.UNCOMMON, _stats(0, 1, 0, 0, 0, 1))
	var rare_gauntlets: Gear = _make_gear_with_affix("Warded Gauntlets", Gear.Slot.HANDS, RarityVisuals.Rarity.RARE, _stats(2, 0, 0, 0, 0, 0))
	var epic_charm: Gear = _make_gear_with_affix("Glowing Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0, 0, 2, 1, 0, 0))
	# Second Charm slot demo item (design-bible §24 "Charm x2") — Common rarity so the level-3
	# companion CAN equip it, distinguishing "not enough Resonance/level" from "works fine".
	var lucky_pebble: Gear = _make_gear("Lucky Pebble", Gear.Slot.CHARM_2, RarityVisuals.Rarity.COMMON, _stats(0, 0, 0, 0, 0, 1))
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var spare_sword: Weapon = _make_weapon("Spare Shortsword", 6.0, RarityVisuals.Rarity.COMMON, slashing, 3)

	# Pre-equip a couple of items so unequip is testable immediately, not just equip-into-empty.
	pc.gear = [common_hat]
	companion.gear = [common_chest]

	inv.gear = [uncommon_cloak, rare_gauntlets, epic_charm, lucky_pebble]
	inv.weapons = [spare_sword]

	# Healing Potions (2026-07-14 combat items menu) — no shop exists yet, so seed a few directly,
	# same placeholder convention already used for the gear/weapon variety above.
	var healing_potion: ConsumableItem = ConsumableItem.new()
	healing_potion.item_type = &"healing_potion"
	healing_potion.display_name = "Healing Potion"
	healing_potion.heal_amount = 30
	healing_potion.effect_type = &"heal"
	healing_potion.quantity = 3
	inv.items = [healing_potion]

	return {
		"pc": pc,
		"companions": [companion],
		"bench": bench,
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

## [param reel_type]/[param reel_count] give this placeholder weapon real action reels (player-
## reported bug, 2026-07-12: the original version left .reels empty, so equipping this weapon —
## displacing a class-native weapon that DOES have reels — left that combatant with a real,
## non-null Weapon that had zero attack reels. Distinct from Combatant.unequip_weapon()'s
## null-fallback fix earlier the same day; this is "a real item with no reels," not "no item."
static func _make_weapon(display_name: String, base_damage: float, rarity: int, reel_type: DamageType, reel_count: int = 3) -> Weapon:
	var w: Weapon = Weapon.new()
	w.display_name = display_name
	w.base_damage = base_damage
	w.rarity = rarity
	for i in range(reel_count):
		w.reels.append(ActionReel.make_default(reel_type))
	return w
