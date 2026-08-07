extends SceneTree

## View-layer smoke: ItemMenuPanel builds one row per distinct (item_type, rarity) stack the party
## owns (2026-08-02 salvaging-and-cooking professions design section 2.4 — extended from the
## original item_type-only keying so two rarities of the same food item both show/stage correctly).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_item_menu_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 25
	potion.quantity = 3
	inv.items = [potion]

	var c: Combatant = Combatant.new()
	c.resource_pool = ResourcePool.new()
	c.display_name = "Basil"
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	var panel: ItemMenuPanel = ItemMenuPanel.new()

	panel.open_for(plan, inv, c)
	_check(panel.row_types().size() == 1 and panel.row_types()[0]["item_type"] == &"healing_potion", "one row per owned (item_type, rarity) stack")
	_check(panel.visible, "open_for shows the panel")

	panel.open_for(plan, inv, c)
	_check(panel.row_types().size() == 1, "re-open rebuilds instead of accumulating rows")

	var got_types: Array[StringName] = []
	var got_rarities: Array = []
	panel.item_pressed.connect(func(item_type: StringName, rarity: int) -> void:
		got_types.append(item_type)
		got_rarities.append(rarity))
	panel.press_row_for_test(&"healing_potion")
	_check(got_types == ([&"healing_potion"] as Array[StringName]), "pressing a row emits item_pressed(item_type, rarity)")
	_check(got_rarities == [RarityVisuals.Rarity.COMMON], "Healing Potion's rarity is COMMON")

	plan.toggle_item(&"healing_potion")
	panel.open_for(plan, inv, c)
	var staged_btn: Button = panel._row_buttons["healing_potion_%d" % RarityVisuals.Rarity.COMMON]
	_check(staged_btn.text.contains("✓"), "staged row's button text shows the checkmark")
	_check(staged_btn.modulate == ItemMenuPanel.COLOR_STAGED, "staged row's button is tinted COLOR_STAGED")
	plan.toggle_item(&"healing_potion")   # un-stage, so it doesn't interfere with the rarity test below

	# Two rarities of the SAME item_type render as two distinct rows and stage independently.
	var rare_potion: ConsumableItem = ConsumableItem.new()
	rare_potion.item_type = &"healing_potion"
	rare_potion.display_name = "Healing Potion"
	rare_potion.rarity = RarityVisuals.Rarity.RARE
	rare_potion.heal_amount = 40
	rare_potion.quantity = 1
	inv.items.append(rare_potion)
	panel.open_for(plan, inv, c)
	_check(panel.row_types().size() == 2, "two rarities of the same item_type render as two separate rows (got %d)" % panel.row_types().size())

	plan.toggle_item(&"healing_potion", RarityVisuals.Rarity.RARE)
	panel.open_for(plan, inv, c)
	var common_btn: Button = panel._row_buttons["healing_potion_%d" % RarityVisuals.Rarity.COMMON]
	var rare_btn: Button = panel._row_buttons["healing_potion_%d" % RarityVisuals.Rarity.RARE]
	_check(not common_btn.text.contains("✓") and rare_btn.text.contains("✓"), "staging the RARE stack leaves the COMMON row un-staged")

	# Live, target-aware description (unchanged from before this task).
	panel.open_for(plan, inv, c)
	_check(_find_info_text(panel, "Basil").find("HP") != -1, "description names the passed ally_target")

	panel.open_for(plan, inv, null)
	_check(_find_info_text(panel, "your target").find("your target") != -1, "null ally_target falls back to a generic phrase")

	panel.open_for(plan, inv, c)
	_check(panel.visible, "re-opened for the close-button check")
	got_types.clear()
	panel.press_close_for_test()
	_check(not panel.visible, "pressing ✕ hides the panel")
	_check(got_types.is_empty(), "pressing ✕ does not emit item_pressed")

	var empty_inv: PartyInventory = PartyInventory.new()
	panel.open_for(plan, empty_inv, c)
	_check(panel.row_types().is_empty(), "zero owned items -> zero rows")

	panel.free()
	quit()

## Finds a row info Label whose text contains [param needle] (there may be several rows now).
func _find_info_text(panel: ItemMenuPanel, needle: String) -> String:
	for child in panel.get_children():
		if child is Label and not child.is_queued_for_deletion() and (child as Label).text.find(needle) != -1:
			return (child as Label).text
	return ""
