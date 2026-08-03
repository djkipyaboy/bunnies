class_name RecipeLibrary
extends RefCounted

## Static registry of Salvaging's armor recipes (2026-08-02 salvaging-and-cooking professions design
## section 3) -- mirrors ShopLibrary/EnemyLibrary's static-registry convention. Cooking's recipes are
## added by a later plan (Task 3 of the Cooking plan) as a separate cooking_recipes() function in
## this same file.
##
## Crafted armor reuses ShopLibrary's exact per-slot stat progression numbers under new "crafted"
## display names, per the design's explicit reuse decision -- these are NOT copies of ShopStockEntry,
## just the same authored numeric table, since crafted gear is generated on demand (not a fixed
## purchasable catalog).

## Salvage yield == craft cost, symmetric (design section 3.1/3.2). [ASSUMPTION] tune by playtest.
const YIELD_AND_COST_BY_SLOT: Dictionary = {
	Gear.Slot.HEADWEAR: 1,
	Gear.Slot.CLOAK: 2,
	Gear.Slot.CHEST: 3,
	Gear.Slot.HANDS: 1,
	Gear.Slot.CHARM: 1,
}

static func armor_recipes() -> Array[Dictionary]:
	return [
		_armor_recipe(Gear.Slot.HEADWEAR, "Handcrafted Cap", &"focus", &"vigor", &"might", {
			RarityVisuals.Rarity.COMMON: _stats(0, 0, 0, 1, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(0, 0, 1, 1, 0, 0),
			RarityVisuals.Rarity.RARE: _stats(0, 0, 0, 3, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(0, 0, 3, 3, 0, 0),
			RarityVisuals.Rarity.LEGENDARY: _stats(0, 0, 4, 4, 0, 0),
		}),
		_armor_recipe(Gear.Slot.CLOAK, "Handcrafted Cloak", &"finesse", &"luck", &"grit", {
			RarityVisuals.Rarity.COMMON: _stats(0, 1, 0, 0, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(0, 1, 0, 0, 0, 1),
			RarityVisuals.Rarity.RARE: _stats(0, 3, 0, 0, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(0, 3, 0, 0, 0, 3),
			RarityVisuals.Rarity.LEGENDARY: _stats(0, 4, 0, 0, 0, 4),
		}),
		_armor_recipe(Gear.Slot.CHEST, "Handcrafted Vest", &"vigor", &"might", &"focus", {
			RarityVisuals.Rarity.COMMON: _stats(0, 0, 1, 0, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(1, 0, 1, 0, 0, 0),
			RarityVisuals.Rarity.RARE: _stats(0, 0, 3, 0, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(3, 0, 3, 0, 0, 0),
			RarityVisuals.Rarity.LEGENDARY: _stats(4, 0, 4, 0, 0, 0),
		}),
		_armor_recipe(Gear.Slot.HANDS, "Handcrafted Gloves", &"might", &"finesse", &"grit", {
			RarityVisuals.Rarity.COMMON: _stats(1, 0, 0, 0, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(1, 1, 0, 0, 0, 0),
			RarityVisuals.Rarity.RARE: _stats(3, 0, 0, 0, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(3, 3, 0, 0, 0, 0),
			RarityVisuals.Rarity.LEGENDARY: _stats(4, 4, 0, 0, 0, 0),
		}),
		_armor_recipe(Gear.Slot.CHARM, "Handcrafted Charm", &"luck", &"focus", &"vigor", {
			RarityVisuals.Rarity.COMMON: _stats(0, 0, 0, 0, 0, 1),
			RarityVisuals.Rarity.UNCOMMON: _stats(0, 0, 0, 1, 0, 1),
			RarityVisuals.Rarity.RARE: _stats(0, 0, 0, 0, 0, 3),
			RarityVisuals.Rarity.EPIC: _stats(0, 0, 0, 3, 0, 3),
			RarityVisuals.Rarity.LEGENDARY: _stats(0, 0, 0, 4, 0, 4),
		}),
	]

static func _armor_recipe(slot: int, display_name: String, primary_stat: StringName, secondary_stat: StringName, tertiary_stat: StringName, stats_by_rarity: Dictionary) -> Dictionary:
	return {
		"slot": slot,
		"display_name": display_name,
		"primary_stat": primary_stat,
		"secondary_stat": secondary_stat,
		"tertiary_stat": tertiary_stat,
		"stats_by_rarity": stats_by_rarity,
	}

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func _find_armor_recipe(slot: int) -> Dictionary:
	for r: Dictionary in armor_recipes():
		if r["slot"] == slot:
			return r
	return {}

static func salvage_yield_for_slot(slot: int) -> int:
	return YIELD_AND_COST_BY_SLOT.get(slot, 0)

static func craft_cost_for_slot(slot: int) -> int:
	return YIELD_AND_COST_BY_SLOT.get(slot, 0)

## Builds a fresh Gear at [param rarity]'s stat table for [param slot]. Returns null for an unknown
## slot (should never happen -- every Gear.Slot value except CHARM_2 has a recipe; CHARM_2 shares
## CHARM's recipe, callers pass CHARM_2 through unchanged so the built Gear's own .slot still reads
## CHARM_2, matching the existing "explicit click reassigns .slot to whichever box was clicked" rule).
static func build_crafted_gear(slot: int, rarity: int) -> Gear:
	var lookup_slot: int = Gear.Slot.CHARM if slot == Gear.Slot.CHARM_2 else slot
	var recipe: Dictionary = _find_armor_recipe(lookup_slot)
	if recipe.is_empty():
		return null
	var g: Gear = Gear.new()
	g.display_name = recipe["display_name"]
	g.slot = slot
	g.rarity = rarity
	var table: Dictionary = recipe["stats_by_rarity"]
	g.stat_bonuses = table.get(rarity, Stats.new())
	return g

static func primary_stat_for_slot(slot: int) -> StringName:
	var recipe: Dictionary = _find_armor_recipe(slot)
	return recipe.get("primary_stat", &"")

static func secondary_stat_for_slot(slot: int) -> StringName:
	var recipe: Dictionary = _find_armor_recipe(slot)
	return recipe.get("secondary_stat", &"")

static func tertiary_stat_for_slot(slot: int) -> StringName:
	var recipe: Dictionary = _find_armor_recipe(slot)
	return recipe.get("tertiary_stat", &"")

## Thin wrapper on RarityVisuals.max_stat_affixes -- kept here so TemperingReelsMinigame (a later
## task) has one obvious profession-facing place to read "how many stat-slot reels" from, without
## needing to know RarityVisuals exists.
static func stat_slot_count_for_rarity(rarity: int) -> int:
	return RarityVisuals.max_stat_affixes(rarity)
