class_name ShopLibrary
extends RefCounted

## Code registry of vendor catalogs (2026-07-17 general store design). One store this pass:
## general_store(), the town Shopkeeper's stock. Every entry is duplicated fresh per call so
## repeated openings never share Resource instances across scene reloads.

static func general_store() -> Array[ShopStockEntry]:
	var entries: Array[ShopStockEntry] = []
	# Headwear (Focus primary / Vigor secondary)
	entries.append(_gear_entry("Cloth Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0,0,0,1,0,0)))
	entries.append(_gear_entry("Hunter's Hood", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,1,1,0,0)))
	entries.append(_gear_entry("Owl-Eye Circlet", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.RARE, _stats(0,0,0,3,0,0)))
	entries.append(_gear_entry("Sage's Coronet", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.EPIC, _stats(0,0,3,3,0,0)))
	entries.append(_gear_entry("Crown of the Elder Oak", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,4,4,0,0)))
	# Cloak (Finesse primary / Luck secondary)
	entries.append(_gear_entry("Traveler's Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.COMMON, _stats(0,1,0,0,0,0)))
	entries.append(_gear_entry("Nimble Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.UNCOMMON, _stats(0,1,0,0,0,1)))
	entries.append(_gear_entry("Shadowstep Cape", Gear.Slot.CLOAK, RarityVisuals.Rarity.RARE, _stats(0,3,0,0,0,0)))
	entries.append(_gear_entry("Cloak of the Fleetfoot", Gear.Slot.CLOAK, RarityVisuals.Rarity.EPIC, _stats(0,3,0,0,0,3)))
	entries.append(_gear_entry("Mantle of the Wind", Gear.Slot.CLOAK, RarityVisuals.Rarity.LEGENDARY, _stats(0,4,0,0,0,4)))
	# Chest (Vigor primary / Might secondary)
	entries.append(_gear_entry("Padded Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, _stats(0,0,1,0,0,0)))
	entries.append(_gear_entry("Riveted Jerkin", Gear.Slot.CHEST, RarityVisuals.Rarity.UNCOMMON, _stats(1,0,1,0,0,0)))
	entries.append(_gear_entry("Bark-Plate Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.RARE, _stats(0,0,3,0,0,0)))
	entries.append(_gear_entry("Warden's Breastplate", Gear.Slot.CHEST, RarityVisuals.Rarity.EPIC, _stats(3,0,3,0,0,0)))
	entries.append(_gear_entry("Heartwood Aegis", Gear.Slot.CHEST, RarityVisuals.Rarity.LEGENDARY, _stats(4,0,4,0,0,0)))
	# Hands (Might primary / Finesse secondary)
	entries.append(_gear_entry("Worn Gloves", Gear.Slot.HANDS, RarityVisuals.Rarity.COMMON, _stats(1,0,0,0,0,0)))
	entries.append(_gear_entry("Gripping Gauntlets", Gear.Slot.HANDS, RarityVisuals.Rarity.UNCOMMON, _stats(1,1,0,0,0,0)))
	entries.append(_gear_entry("Ironclaw Fists", Gear.Slot.HANDS, RarityVisuals.Rarity.RARE, _stats(3,0,0,0,0,0)))
	entries.append(_gear_entry("Gauntlets of the Vanguard", Gear.Slot.HANDS, RarityVisuals.Rarity.EPIC, _stats(3,3,0,0,0,0)))
	entries.append(_gear_entry("Fists of the Ancient Oak", Gear.Slot.HANDS, RarityVisuals.Rarity.LEGENDARY, _stats(4,4,0,0,0,0)))
	# Charm variant A (Luck primary / Focus secondary) — both Charm boxes accept either variant
	entries.append(_gear_entry("Rabbit's Foot Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.COMMON, _stats(0,0,0,0,0,1)))
	entries.append(_gear_entry("Four-Leaf Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,0,1,0,1)))
	entries.append(_gear_entry("Gambler's Coin", Gear.Slot.CHARM, RarityVisuals.Rarity.RARE, _stats(0,0,0,0,0,3)))
	entries.append(_gear_entry("Charm of Fortune's Favor", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0,0,0,3,0,3)))
	entries.append(_gear_entry("The Wishing Amber", Gear.Slot.CHARM, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,0,4,0,4)))
	# Charm variant B (Grit primary / Vigor secondary)
	entries.append(_gear_entry("Sturdy Bead", Gear.Slot.CHARM, RarityVisuals.Rarity.COMMON, _stats(0,0,0,0,1,0)))
	entries.append(_gear_entry("Ironwood Talisman", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,1,0,1,0)))
	entries.append(_gear_entry("Bulwark Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.RARE, _stats(0,0,0,0,3,0)))
	entries.append(_gear_entry("Charm of Unshakable Resolve", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0,0,3,0,3,0)))
	entries.append(_gear_entry("Heart of the Mountain", Gear.Slot.CHARM, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,4,0,4,0)))
	# Weapons (Common/Uncommon only, per player direction — no stat_bonuses field on Weapon)
	entries.append(_weapon_entry("Journeyman's Blade", RarityVisuals.Rarity.COMMON, 6.0))
	entries.append(_weapon_entry("Honed Shortsword", RarityVisuals.Rarity.UNCOMMON, 8.0))
	# Healing Potions
	entries.append(_potion_entry())
	return entries

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func _gear_entry(display_name: String, slot: int, rarity: int, stats: Stats) -> ShopStockEntry:
	var g: Gear = Gear.new()
	g.display_name = display_name
	g.slot = slot
	g.rarity = rarity
	g.stat_bonuses = stats
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = g
	e.price = 1
	e.stock = 3
	return e

static func _weapon_entry(display_name: String, rarity: int, base_damage: float) -> ShopStockEntry:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.display_name = display_name
	w.rarity = rarity
	w.base_damage = base_damage
	for i in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = w
	e.price = 1
	e.stock = 3
	return e

static func _potion_entry() -> ShopStockEntry:
	var p: ConsumableItem = ConsumableItem.new()
	p.item_type = &"healing_potion"
	p.display_name = "Healing Potion"
	p.heal_amount = 30
	p.quantity = 1   # per-unit template; ShopPanel buys one unit at a time
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = p
	e.price = 1
	e.stock = 99
	return e
