extends SceneTree

## View-layer smoke: InventoryMenuPanel's Materials and Quest Items tabs (2026-07-12,
## player-requested — gathered materials had nowhere to be seen). Both are plain read-only lists,
## not part of the equip-selection grid.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.base_stats = Stats.new()
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault, true, &"materials")

	_check(panel.active_tab_for_test() == &"materials", "initial_tab opens directly to the Materials tab")
	_check(panel.list_row_count_for_test() == 1, "an empty Materials tab shows exactly one row (the placeholder)")
	_check(panel.list_row_text_for_test(0) == "No materials gathered yet.", "the empty Materials tab shows its placeholder message")

	var berries: CraftingMaterial = CraftingMaterial.new()
	berries.display_name = "Wild Berries"
	berries.material_type = &"forage_herb"
	berries.quantity = 3
	var fish: CraftingMaterial = CraftingMaterial.new()
	fish.display_name = "Freshwater Fish"
	fish.material_type = &"fish_meat"
	fish.quantity = 1
	inv.materials = [berries, fish]

	panel.switch_tab_for_test(&"materials")   # re-render with the now-populated inventory
	_check(panel.list_row_count_for_test() == 2, "a populated Materials tab shows one row per material")
	_check(panel.list_row_text_for_test(0) == "Wild Berries x3", "the Materials tab shows name and quantity")
	_check(panel.list_row_text_for_test(1) == "Freshwater Fish x1", "the Materials tab shows every gathered material")

	# --- Quest Items tab: currently always empty (no quest system exists yet) — a working shell. ---
	panel.switch_tab_for_test(&"quest")
	_check(panel.active_tab_for_test() == &"quest", "switching to the Quest tab works")
	_check(panel.list_row_count_for_test() == 1, "an empty Quest tab shows exactly one row (the placeholder)")
	_check(panel.list_row_text_for_test(0) == "No quest items yet.", "the empty Quest tab shows its placeholder message")

	var key: QuestItem = QuestItem.new()
	key.display_name = "Rusty Key"
	key.item_id = &"dungeon_key"
	inv.quest_items = [key]
	panel.switch_tab_for_test(&"quest")
	_check(panel.list_row_count_for_test() == 1, "a populated Quest tab shows one row per quest item")
	_check(panel.list_row_text_for_test(0) == "Rusty Key", "the Quest tab shows the item's real display_name, not a placeholder")

	var sigil: QuestItem = QuestItem.new()
	sigil.display_name = "Sunken Sigil"
	sigil.item_id = &"sunken_sigil"
	sigil.description = "A cold, sigil-etched stone that hums faintly."
	inv.quest_items = [key, sigil]
	panel.switch_tab_for_test(&"quest")
	_check(panel.list_row_tooltip_for_test(0) == "", "a quest item with no description shows no tooltip")
	_check(panel.list_row_tooltip_for_test(1) == "A cold, sigil-etched stone that hums faintly.", "a quest item's description shows as its row's tooltip")

	# Switching back to Bag still works — neither new tab wedges the panel.
	panel.switch_tab_for_test(&"bag")
	_check(panel.active_tab_for_test() == &"bag", "switching back to Bag works normally")

	panel.free()
	quit()
