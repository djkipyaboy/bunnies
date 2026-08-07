extends SceneTree

## Regression test (Task 6, 2026-08-07 professions-playtest-fixes): InventoryMenuPanel.
## slot_display_color() used to unconditionally return flat gray for a ConsumableItem, with a doc
## comment claiming "a Consumable has no rarity" -- stale as of the 2026-08-02 salvaging-and-
## cooking-professions spec, which added ConsumableItem.rarity. Cooked food and the pre-existing
## Healing Potion both rendered gray in the Bag tab regardless of their real (Common+) rarity.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var common_item: ConsumableItem = ConsumableItem.new()
	common_item.item_type = &"healing_potion"
	common_item.display_name = "Healing Potion"
	common_item.rarity = RarityVisuals.Rarity.COMMON

	var rare_item: ConsumableItem = ConsumableItem.new()
	rare_item.item_type = &"roasted_fish"
	rare_item.display_name = "Roasted Fish"
	rare_item.rarity = RarityVisuals.Rarity.RARE

	_check(InventoryMenuPanel.slot_display_color(common_item) == RarityVisuals.color(RarityVisuals.Rarity.COMMON), "a Common ConsumableItem renders in RarityVisuals' Common color, not flat gray")
	_check(InventoryMenuPanel.slot_display_color(rare_item) == RarityVisuals.color(RarityVisuals.Rarity.RARE), "a Rare ConsumableItem renders in RarityVisuals' Rare color")
	_check(InventoryMenuPanel.slot_display_color(common_item) != InventoryMenuPanel.slot_display_color(rare_item), "different rarities render in visibly different colors")

	print("ok InventoryMenuPanel consumable rarity color test complete")
	quit()
