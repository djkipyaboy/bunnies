class_name SalvageSystem
extends RefCounted

## Break Down / Craft orchestration for Salvaging (2026-08-02 salvaging-and-cooking professions
## design section 3). Pure logic, mirrors ConsumableEffects' "static-only dispatch" convention --
## no instance state, so the UI panel (a later task) never has to construct one of these.

const SCRAP_MATERIAL_TYPE: StringName = &"salvage_scrap"

## Consumes [param gear_item] from [param inventory]'s Bag and grants Scrap at its rarity. Returns
## the granted (or merged-into) CraftingMaterial. Caller is responsible for confirming gear_item is
## actually unequipped/in the Bag before calling -- mirrors the existing Discard flow's own contract.
static func break_down(gear_item: Gear, inventory: PartyInventory) -> CraftingMaterial:
	inventory.gear.erase(gear_item)
	var yield_amount: int = RecipeLibrary.salvage_yield_for_slot(gear_item.slot)
	var m: CraftingMaterial = CraftingMaterial.new()
	m.material_type = SCRAP_MATERIAL_TYPE
	m.display_name = "Salvage Scrap"
	m.rarity = gear_item.rarity
	m.quantity = yield_amount
	inventory.give_material(m)
	# give_material() may have merged into a pre-existing stack rather than appending `m` itself --
	# return whichever CraftingMaterial instance now actually holds this rarity's stack.
	for existing: CraftingMaterial in inventory.materials:
		if existing.material_type == SCRAP_MATERIAL_TYPE and existing.rarity == gear_item.rarity:
			return existing
	return m

## Whether the party owns enough Scrap of [param rarity] to afford [param slot]'s recipe.
static func can_craft(slot: int, rarity: int, inventory: PartyInventory) -> bool:
	var cost: int = RecipeLibrary.craft_cost_for_slot(slot)
	if cost <= 0:
		return false
	for m: CraftingMaterial in inventory.materials:
		if m.material_type == SCRAP_MATERIAL_TYPE and m.rarity == rarity:
			return m.quantity >= cost
	return false

## Crafts [param slot] at [param rarity]: consumes Scrap, adds [param bonus_stats] (Tempering Reels'
## resolve() output, or null to skip it) on top of the recipe's deterministic base, and grants the
## result via try_give_gear (capacity-gated, like loot/shop). Returns null (grants nothing, consumes
## nothing) when can_craft() would be false.
static func craft(slot: int, rarity: int, inventory: PartyInventory, bonus_stats: Stats = null) -> Gear:
	if not can_craft(slot, rarity, inventory):
		return null
	var cost: int = RecipeLibrary.craft_cost_for_slot(slot)
	for m: CraftingMaterial in inventory.materials:
		if m.material_type == SCRAP_MATERIAL_TYPE and m.rarity == rarity:
			m.quantity -= cost
			if m.quantity <= 0:
				inventory.materials.erase(m)
			break
	var g: Gear = RecipeLibrary.build_crafted_gear(slot, rarity)
	if bonus_stats != null:
		g.stat_bonuses = g.stat_bonuses.plus(bonus_stats)
	if not inventory.try_give_gear(g):
		return null
	return g
