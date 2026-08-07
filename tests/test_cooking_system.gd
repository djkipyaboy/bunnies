extends SceneTree

## CookingSystem: Cook orchestration for Cooking (2026-08-02 salvaging-and-cooking professions
## design section 4).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(not CookingSystem.can_cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv), "can_cook() is false with zero Wild Berries owned")

	var berries: CraftingMaterial = CraftingMaterial.new()
	berries.material_type = &"forage_herb"
	berries.rarity = RarityVisuals.Rarity.COMMON
	berries.quantity = 1
	inv.give_material(berries)
	_check(not CookingSystem.can_cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv), "can_cook() is false when owned berries (1) are under the recipe's requirement (2)")

	berries.quantity = 2
	_check(CookingSystem.can_cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv), "can_cook() is true once owned berries meet the requirement exactly")

	var jam: ConsumableItem = CookingSystem.cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv)
	_check(jam != null, "cook() returns a real ConsumableItem when affordable")
	_check(jam.item_type == &"wildberry_jam" and jam.rarity == RarityVisuals.Rarity.COMMON, "the cooked item has the requested type/rarity")
	_check(jam.heal_amount == 15, "the cooked item's heal_amount matches the recipe's Common tier")
	_check(jam.effect_type == &"heal", "the cooked item reuses the existing heal effect_type -- no new plumbing needed")
	_check(inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON) == jam, "the cooked item lands in the Bag")
	_check(berries.quantity == 0, "cooking consumed both berries")

	var poor_inv: PartyInventory = PartyInventory.new()
	_check(CookingSystem.cook(&"roasted_fish", RarityVisuals.Rarity.COMMON, poor_inv) == null, "cook() returns null (and grants nothing) when unaffordable")
	_check(poor_inv.items.is_empty(), "no phantom item was added on a failed cook")

	# Roasted Fish accepts ANY of the 3 fish material_types interchangeably.
	var fish_inv: PartyInventory = PartyInventory.new()
	var medium_fish: CraftingMaterial = CraftingMaterial.new()
	medium_fish.material_type = &"fish_medium"
	medium_fish.rarity = RarityVisuals.Rarity.RARE
	medium_fish.quantity = 1
	fish_inv.give_material(medium_fish)
	_check(CookingSystem.can_cook(&"roasted_fish", RarityVisuals.Rarity.RARE, fish_inv), "Roasted Fish accepts fish_medium (a non-first material_type in its accepted list)")
	var roasted: ConsumableItem = CookingSystem.cook(&"roasted_fish", RarityVisuals.Rarity.RARE, fish_inv)
	_check(roasted != null and roasted.heal_amount == 30, "Roasted Fish heals 30 at Rare")
	_check(medium_fish.quantity == 0, "the specific fish type consumed was decremented")

	# A bonus_quantity > 0 (Second Helping's output) grants extra units in the same stack.
	var bonus_inv: PartyInventory = PartyInventory.new()
	var more_berries: CraftingMaterial = CraftingMaterial.new()
	more_berries.material_type = &"forage_herb"
	more_berries.rarity = RarityVisuals.Rarity.EPIC
	more_berries.quantity = 2
	bonus_inv.give_material(more_berries)
	var bonus_jam: ConsumableItem = CookingSystem.cook(&"wildberry_jam", RarityVisuals.Rarity.EPIC, bonus_inv, 2)
	_check(bonus_jam.quantity == 3, "bonus_quantity=2 grants 1 (base) + 2 (bonus) = 3 units (got %d)" % bonus_jam.quantity)
	_check(more_berries.quantity == 0, "cooking consumed all bonus berries")

	# cook() must not consume materials when the Bag is full (Bag already at capacity, genuinely new item_type/rarity).
	var full_inv: PartyInventory = PartyInventory.new()
	# Deliberately fill the Bag to reach capacity
	for i in range(20):  # BASE_BAG_CAPACITY = 20, so this reaches the base capacity
		var dummy_gear: Gear = Gear.new()
		dummy_gear.slot = Gear.Slot.HEADWEAR
		dummy_gear.rarity = RarityVisuals.Rarity.COMMON
		dummy_gear.display_name = "Dummy %d" % i
		if not full_inv.try_give_gear(dummy_gear):
			break
	var full_materials: CraftingMaterial = CraftingMaterial.new()
	full_materials.material_type = &"forage_herb"
	full_materials.rarity = RarityVisuals.Rarity.COMMON
	full_materials.quantity = 2
	full_inv.give_material(full_materials)
	_check(not full_inv.can_add_to_bag(), "Bag is truly at capacity")
	var failed_cook: ConsumableItem = CookingSystem.cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, full_inv)
	_check(failed_cook == null, "cook() returns null when the Bag is full")
	_check(full_materials.quantity == 2, "materials are completely untouched when cook() fails due to full Bag (not consumed)")

	print("ok CookingSystem smoke test complete")
	quit()
