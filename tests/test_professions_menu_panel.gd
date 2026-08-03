extends SceneTree

## ProfessionsMenuPanel: Salvaging's UI (2026-08-02 salvaging-and-cooking professions design section
## 5). This task covers only the Salvaging section -- a later plan (Cooking) adds a second section.
##
## Uses _initialize()/await process_frame (mirroring tests/test_tempering_reels_panel.gd and
## tests/test_foraging_panel.gd) rather than _init(), since ProfessionsMenuPanel's own _ready()
## constructs its child TemperingReelsPanel -- a plain _init() runs before the SceneTree has
## processed a frame, so _tempering_panel would still be null when open_for() is called.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var chest: Gear = Gear.new()
	chest.display_name = "Old Vest"
	chest.slot = Gear.Slot.CHEST
	chest.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(chest)

	var panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(panel)
	await process_frame

	panel.open_for(inv)
	_check(panel.is_open(), "open_for() shows the panel")

	# --- Break Down ---
	panel.select_breakdown_item_for_test(0)
	panel.press_breakdown_confirm_for_test()
	_check(inv.gear.is_empty(), "confirming Break Down consumes the selected Gear")
	_check(inv.materials.size() == 1 and inv.materials[0].rarity == RarityVisuals.Rarity.RARE and inv.materials[0].quantity == 3, "Break Down grants Rare Scrap x3 (Chest's yield)")

	# --- Craft (deterministic, no Tempering Reels) ---
	panel.select_craft_slot_for_test(Gear.Slot.HEADWEAR)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.COMMON)
	_check(not panel.can_confirm_craft_for_test(), "can't craft Headwear yet -- the party only owns Rare Scrap, Headwear needs Common")

	var common_scrap: CraftingMaterial = CraftingMaterial.new()
	common_scrap.material_type = &"salvage_scrap"
	common_scrap.rarity = RarityVisuals.Rarity.COMMON
	common_scrap.quantity = 1
	inv.give_material(common_scrap)
	_check(panel.can_confirm_craft_for_test(), "can craft Headwear now that 1 Common Scrap is owned (its cost)")

	panel.press_craft_confirm_for_test()
	_check(inv.gear.size() == 1 and inv.gear[0].slot == Gear.Slot.HEADWEAR, "confirming Craft (no Tempering Reels) grants the deterministic Headwear")
	_check(not panel.tempering_panel_for_test().is_open(), "the Tempering Reels panel never opened since it wasn't toggled on")

	# --- Craft with Tempering Reels opted in ---
	var scrap2: CraftingMaterial = CraftingMaterial.new()
	scrap2.material_type = &"salvage_scrap"
	scrap2.rarity = RarityVisuals.Rarity.RARE
	scrap2.quantity = 3
	inv.give_material(scrap2)
	panel.select_craft_slot_for_test(Gear.Slot.CHEST)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	panel.toggle_tempering_for_test()
	panel.press_craft_confirm_for_test()
	_check(panel.tempering_panel_for_test().is_open(), "confirming Craft with Tempering Reels toggled on opens the mini-game instead of granting immediately")
	_check(inv.gear.size() == 1, "no new Gear was granted yet -- the craft is still pending the mini-game's result")

	for i in range(panel.tempering_panel_for_test().reel_count_for_test()):
		panel.tempering_panel_for_test().press_stop_for_test(i)
	panel.tempering_panel_for_test().press_confirm_for_test()
	_check(inv.gear.size() == 2, "confirming the Tempering Reels result finally grants the crafted Chest")
	_check(inv.gear[1].slot == Gear.Slot.CHEST, "the granted Gear is the Chest that was staged")

	print("ok ProfessionsMenuPanel (Salvaging) smoke test complete")
	quit()
