extends SceneTree

## RecipeLibrary: static data for Salvaging's 5 armor recipes (2026-08-02 salvaging-and-cooking
## professions design section 3). Mirrors ShopLibrary's static-registry convention.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var recipes: Array[Dictionary] = RecipeLibrary.armor_recipes()
	_check(recipes.size() == 5, "exactly 5 armor recipes, one per slot (got %d)" % recipes.size())

	var slots_seen: Array = []
	for r: Dictionary in recipes:
		slots_seen.append(r["slot"])
	_check(slots_seen.has(Gear.Slot.HEADWEAR) and slots_seen.has(Gear.Slot.CLOAK) and slots_seen.has(Gear.Slot.CHEST) and slots_seen.has(Gear.Slot.HANDS) and slots_seen.has(Gear.Slot.CHARM), "every armor slot has exactly one recipe")
	_check(not slots_seen.has(Gear.Slot.CHARM_2), "no separate CHARM_2 recipe -- one Charm recipe covers both boxes")

	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.HEADWEAR) == 1, "Headwear yields 1 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CLOAK) == 2, "Cloak yields 2 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CHEST) == 3, "Chest yields 3 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.HANDS) == 1, "Hands yields 1 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CHARM) == 1, "Charm yields 1 Scrap")
	_check(RecipeLibrary.craft_cost_for_slot(Gear.Slot.CHEST) == RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CHEST), "craft cost mirrors salvage yield 1:1 (symmetric)")

	var chest_common: Gear = RecipeLibrary.build_crafted_gear(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON)
	_check(chest_common != null, "build_crafted_gear() returns a real Gear for a known slot")
	_check(chest_common.slot == Gear.Slot.CHEST, "the built Gear has the requested slot")
	_check(chest_common.rarity == RarityVisuals.Rarity.COMMON, "the built Gear has the requested rarity")
	_check(chest_common.display_name != "", "the built Gear has a non-blank display name")
	_check(chest_common.stat_bonuses.vigor == 1, "Chest's Common stat table matches the shop's own Padded Vest numbers (Vigor 1)")

	var chest_legendary: Gear = RecipeLibrary.build_crafted_gear(Gear.Slot.CHEST, RarityVisuals.Rarity.LEGENDARY)
	_check(chest_legendary.stat_bonuses.vigor == 4 and chest_legendary.stat_bonuses.might == 4, "Chest's Legendary stat table matches the shop's own Heartwood Aegis numbers (Vigor 4 / Might 4)")
	_check(chest_common.display_name == chest_legendary.display_name, "the recipe's display name is constant across rarities -- color/tag communicates tier, not the name")

	_check(RecipeLibrary.primary_stat_for_slot(Gear.Slot.CHEST) == &"vigor", "Chest's primary stat is Vigor")
	_check(RecipeLibrary.secondary_stat_for_slot(Gear.Slot.CHEST) == &"might", "Chest's secondary stat is Might")
	_check(RecipeLibrary.tertiary_stat_for_slot(Gear.Slot.CHEST) == &"focus", "Chest's tertiary stat (Tempering Reels' bonus_tertiary target) is Focus")

	_check(RecipeLibrary.stat_slot_count_for_rarity(RarityVisuals.Rarity.COMMON) == 1, "Common has 1 stat slot")
	_check(RecipeLibrary.stat_slot_count_for_rarity(RarityVisuals.Rarity.RARE) == 1, "Rare has 1 stat slot (fewer than Uncommon -- it trades the 2nd for a reel-affix slot, per RarityVisuals)")
	_check(RecipeLibrary.stat_slot_count_for_rarity(RarityVisuals.Rarity.LEGENDARY) == 2, "Legendary has 2 stat slots")

	print("ok RecipeLibrary armor recipes smoke test complete")
	quit()
