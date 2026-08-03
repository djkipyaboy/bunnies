extends SceneTree

## SalvageSystem: Break Down / Craft orchestration for Salvaging (2026-08-02 salvaging-and-cooking
## professions design section 3).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# --- break_down() ---
	var inv: PartyInventory = PartyInventory.new()
	var chest: Gear = Gear.new()
	chest.display_name = "Padded Vest"
	chest.slot = Gear.Slot.CHEST
	chest.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(chest)

	var granted: CraftingMaterial = SalvageSystem.break_down(chest, inv)
	_check(inv.gear.is_empty(), "break_down() removes the salvaged Gear from the Bag")
	_check(granted.material_type == &"salvage_scrap", "break_down() grants the universal salvage_scrap type")
	_check(granted.rarity == RarityVisuals.Rarity.RARE, "the granted material's rarity mirrors the salvaged gear's rarity")
	_check(granted.quantity == 3, "Chest yields 3 Scrap (matching RecipeLibrary.salvage_yield_for_slot)")
	_check(inv.materials.size() == 1 and inv.materials[0].quantity == 3, "the yield lands in the party's materials via give_material()")

	var headwear: Gear = Gear.new()
	headwear.slot = Gear.Slot.HEADWEAR
	headwear.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(headwear)
	SalvageSystem.break_down(headwear, inv)
	_check(inv.materials.size() == 1 and inv.materials[0].quantity == 4, "a second salvage of the SAME rarity stacks onto the existing Scrap entry (3 + 1 = 4)")

	# --- can_craft() / craft() ---
	var craft_inv: PartyInventory = PartyInventory.new()
	_check(not SalvageSystem.can_craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv), "can_craft() is false with zero Scrap owned")

	var starter_scrap: CraftingMaterial = CraftingMaterial.new()
	starter_scrap.material_type = &"salvage_scrap"
	starter_scrap.rarity = RarityVisuals.Rarity.COMMON
	starter_scrap.quantity = 2
	craft_inv.give_material(starter_scrap)
	_check(not SalvageSystem.can_craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv), "can_craft() is false when owned Scrap (2) is under the Chest cost (3)")

	starter_scrap.quantity = 3
	_check(SalvageSystem.can_craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv), "can_craft() is true once owned Scrap meets the cost exactly")

	var crafted: Gear = SalvageSystem.craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv)
	_check(crafted != null, "craft() returns a real Gear when affordable")
	_check(crafted.slot == Gear.Slot.CHEST and crafted.rarity == RarityVisuals.Rarity.COMMON, "the crafted Gear has the requested slot/rarity")
	_check(craft_inv.gear.has(crafted), "the crafted Gear lands in the Bag")
	_check(starter_scrap.quantity == 0, "crafting consumed all 3 Scrap")

	var poor_inv: PartyInventory = PartyInventory.new()
	_check(SalvageSystem.craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, poor_inv) == null, "craft() returns null (and grants nothing) when unaffordable")
	_check(poor_inv.gear.is_empty(), "no phantom Gear was added on a failed craft")

	# --- craft() with a Tempering Reels bonus delta ---
	var bonus_inv: PartyInventory = PartyInventory.new()
	var bonus_scrap: CraftingMaterial = CraftingMaterial.new()
	bonus_scrap.material_type = &"salvage_scrap"
	bonus_scrap.rarity = RarityVisuals.Rarity.COMMON
	bonus_scrap.quantity = 3
	bonus_inv.give_material(bonus_scrap)
	var delta: Stats = Stats.new()
	delta.vigor = 5
	var tempered: Gear = SalvageSystem.craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, bonus_inv, delta)
	_check(tempered.stat_bonuses.vigor == 1 + 5, "a passed bonus_stats delta is ADDED onto the recipe's deterministic base (1 + 5 = 6, got %d)" % tempered.stat_bonuses.vigor)

	# --- CHARM_2 normalization (RecipeLibrary's yield/cost table has no CHARM_2 entry, only CHARM) ---
	var charm2_inv: PartyInventory = PartyInventory.new()
	var charm2_item: Gear = Gear.new()
	charm2_item.slot = Gear.Slot.CHARM_2
	charm2_item.rarity = RarityVisuals.Rarity.UNCOMMON
	charm2_inv.gear.append(charm2_item)
	var charm2_granted: CraftingMaterial = SalvageSystem.break_down(charm2_item, charm2_inv)
	_check(charm2_granted.quantity == RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CHARM), "break_down() normalizes CHARM_2 -> CHARM for the yield lookup instead of yielding 0 (got %d)" % charm2_granted.quantity)

	_check(SalvageSystem.can_craft(Gear.Slot.CHARM_2, RarityVisuals.Rarity.UNCOMMON, charm2_inv), "can_craft() normalizes CHARM_2 -> CHARM for the cost lookup")
	var charm2_crafted: Gear = SalvageSystem.craft(Gear.Slot.CHARM_2, RarityVisuals.Rarity.UNCOMMON, charm2_inv)
	_check(charm2_crafted != null, "craft() can build into the CHARM_2 slot")
	_check(charm2_crafted.slot == Gear.Slot.CHARM_2, "the crafted Gear's own .slot preserves CHARM_2 (not normalized away on the output)")

	# --- craft() must not lose Scrap when the Bag is full (try_give_gear fails) ---
	var full_inv: PartyInventory = PartyInventory.new()
	for i in range(full_inv.bag_capacity()):
		full_inv.gear.append(Gear.new())
	var full_scrap: CraftingMaterial = CraftingMaterial.new()
	full_scrap.material_type = &"salvage_scrap"
	full_scrap.rarity = RarityVisuals.Rarity.COMMON
	full_scrap.quantity = 3
	full_inv.give_material(full_scrap)
	_check(not full_inv.can_add_to_bag(), "test setup: the Bag is genuinely full before craft() is called")
	var full_bag_result: Gear = SalvageSystem.craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, full_inv)
	_check(full_bag_result == null, "craft() returns null when the Bag is full even though Scrap is sufficient")
	_check(full_scrap.quantity == 3, "craft() did NOT spend the Scrap when the Bag-full grant failed (still 3)")
	_check(full_inv.gear.size() == full_inv.bag_capacity(), "no phantom Gear was added to the already-full Bag")

	print("ok SalvageSystem smoke test complete")
	quit()
