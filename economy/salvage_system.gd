class_name SalvageSystem
extends RefCounted

## Break Down / Craft orchestration for Salvaging (2026-08-02 salvaging-and-cooking professions
## design section 3). Pure logic, mirrors ConsumableEffects' "static-only dispatch" convention --
## no instance state, so the UI panel (a later task) never has to construct one of these.

const SCRAP_MATERIAL_TYPE: StringName = &"salvage_scrap"

## Consumes [param gear_item] from [param inventory]'s Bag and grants Scrap at its rarity. Returns
## the granted (or merged-into) CraftingMaterial. Caller is responsible for confirming gear_item is
## actually unequipped/in the Bag before calling -- mirrors the existing Discard flow's own contract.
static func break_down(gear_item: Gear, inventory: PartyInventory, log_fn: Callable = Callable()) -> CraftingMaterial:
	var gear_name: String = gear_item.display_name
	var gear_rarity: int = gear_item.rarity
	inventory.gear.erase(gear_item)
	# RecipeLibrary's yield/cost table has no CHARM_2 entry -- normalize the same way
	# build_crafted_gear() already does, without altering gear_item.slot itself.
	var lookup_slot: int = Gear.Slot.CHARM if gear_item.slot == Gear.Slot.CHARM_2 else gear_item.slot
	var yield_amount: int = RecipeLibrary.salvage_yield_for_slot(lookup_slot)
	var m: CraftingMaterial = CraftingMaterial.new()
	m.material_type = SCRAP_MATERIAL_TYPE
	m.display_name = "Salvage Scrap"
	m.rarity = gear_rarity
	m.quantity = yield_amount
	inventory.give_material(m)
	# give_material() may have merged into a pre-existing stack rather than appending `m` itself --
	# return whichever CraftingMaterial instance now actually holds this rarity's stack.
	var result: CraftingMaterial = m
	for existing: CraftingMaterial in inventory.materials:
		if existing.material_type == SCRAP_MATERIAL_TYPE and existing.rarity == gear_rarity:
			result = existing
			break
	if log_fn.is_valid():
		log_fn.call("Salvaged %s → %dx Salvage Scrap (%s)." % [gear_name, yield_amount, RarityVisuals.display_name(gear_rarity)])
	return result

## Whether the party owns enough Scrap of [param rarity] to afford [param slot]'s recipe.
static func can_craft(slot: int, rarity: int, inventory: PartyInventory) -> bool:
	# Normalize CHARM_2 -> CHARM for the cost lookup only (mirrors build_crafted_gear()) -- the
	# caller's own slot value is never touched here.
	var lookup_slot: int = Gear.Slot.CHARM if slot == Gear.Slot.CHARM_2 else slot
	var cost: int = RecipeLibrary.craft_cost_for_slot(lookup_slot)
	if cost <= 0:
		return false
	for m: CraftingMaterial in inventory.materials:
		if m.material_type == SCRAP_MATERIAL_TYPE and m.rarity == rarity:
			return m.quantity >= cost
	return false

## Crafts [param slot] at [param rarity]: consumes Scrap, adds [param bonus_stats] (Tempering Reels'
## resolve() output, or null to skip it) on top of the recipe's deterministic base, and grants the
## result via try_give_gear (capacity-gated, like loot/shop). Returns null and leaves BOTH the Bag
## and the Scrap stack untouched whenever the craft can't fully complete -- either because
## can_craft() is false, or because the Bag is full when it comes time to actually grant the result
## (Scrap must never be spent for nothing -- build the Gear and attempt the grant BEFORE touching
## the Scrap stack, so a failed try_give_gear() has nothing left to refund).
static func craft(slot: int, rarity: int, inventory: PartyInventory, bonus_stats: Stats = null, log_fn: Callable = Callable()) -> Gear:
	if not can_craft(slot, rarity, inventory):
		return null
	# Normalize CHARM_2 -> CHARM for the cost lookup only -- build_crafted_gear() below preserves
	# the caller's original `slot` (CHARM_2 included) on the output Gear itself, unchanged.
	var lookup_slot: int = Gear.Slot.CHARM if slot == Gear.Slot.CHARM_2 else slot
	var cost: int = RecipeLibrary.craft_cost_for_slot(lookup_slot)
	var g: Gear = RecipeLibrary.build_crafted_gear(slot, rarity)
	if bonus_stats != null:
		g.stat_bonuses = g.stat_bonuses.plus(bonus_stats)
	if not inventory.try_give_gear(g):
		return null
	for m: CraftingMaterial in inventory.materials:
		if m.material_type == SCRAP_MATERIAL_TYPE and m.rarity == rarity:
			m.quantity -= cost
			if m.quantity <= 0:
				inventory.materials.erase(m)
			break
	if log_fn.is_valid():
		log_fn.call("Crafted %s (%s)." % [g.display_name, RarityVisuals.display_name(rarity)])
	return g
