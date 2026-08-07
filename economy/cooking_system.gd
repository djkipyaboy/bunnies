class_name CookingSystem
extends RefCounted

## Cook orchestration for Cooking (2026-08-02 salvaging-and-cooking professions design section 4).
## Pure logic, mirrors SalvageSystem/ConsumableEffects' static-only-dispatch convention.

## Whether the party owns enough of ANY ONE accepted input material (at [param rarity]) to afford
## [param recipe_id]'s requirement -- a recipe accepting multiple material_types (Roasted Fish) is
## satisfied by any single one of them meeting the quantity alone, never summed across types.
static func can_cook(recipe_id: StringName, rarity: int, inventory: PartyInventory) -> bool:
	var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(recipe_id)
	if recipe.is_empty():
		return false
	return _matching_stack(recipe, rarity, inventory) != null

static func _matching_stack(recipe: Dictionary, rarity: int, inventory: PartyInventory) -> CraftingMaterial:
	var accepted_types: Array = recipe["input_material_types"]
	var needed: int = recipe["input_quantity"]
	for m: CraftingMaterial in inventory.materials:
		if m.material_type in accepted_types and m.rarity == rarity and m.quantity >= needed:
			return m
	return null

## Cooks [param recipe_id] at [param rarity]: consumes the matching input material stack, grants
## `1 + bonus_quantity` units of the recipe's output ConsumableItem at [param rarity] (Second
## Helping's bonus, or 0 to skip it), via try_give_item (capacity-gated, like loot/shop). Returns
## null (grants nothing, consumes nothing) when can_cook() would be false.
static func cook(recipe_id: StringName, rarity: int, inventory: PartyInventory, bonus_quantity: int = 0) -> ConsumableItem:
	var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(recipe_id)
	if recipe.is_empty():
		return null
	var stack: CraftingMaterial = _matching_stack(recipe, rarity, inventory)
	if stack == null:
		return null
	stack.quantity -= int(recipe["input_quantity"])
	if stack.quantity <= 0:
		inventory.materials.erase(stack)

	var item: ConsumableItem = ConsumableItem.new()
	item.item_type = recipe["output_item_type"]
	item.display_name = recipe["display_name"]
	item.rarity = rarity
	item.quantity = 1 + bonus_quantity
	item.effect_type = &"heal"
	var heal_table: Dictionary = recipe["heal_by_rarity"]
	item.heal_amount = int(heal_table.get(rarity, 0))

	if not inventory.try_give_item(item):
		return null
	# try_give_item() may have merged into a pre-existing stack rather than appending `item` itself
	# -- return whichever ConsumableItem instance now actually holds this (type, rarity) stack,
	# mirroring SalvageSystem.break_down()'s identical re-lookup.
	return inventory.find_item(item.item_type, rarity)
