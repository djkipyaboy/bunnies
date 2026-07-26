extends SceneTree

## Out-of-combat item-use (2026-07-26 design). This file grows across Tasks 3-5 of the same plan —
## Task 3 covers Bag-tab display only; later tasks in this same plan append the action-row and
## targeting-flow checks below this point.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_potion(heal_amount: int, quantity: int) -> ConsumableItem:
	var item: ConsumableItem = ConsumableItem.new()
	item.item_type = &"healing_potion"
	item.display_name = "Healing Potion"
	item.heal_amount = heal_amount
	item.effect_type = &"heal"
	item.quantity = quantity
	return item

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.display_name = "Martin"
	pc.level = 9
	pc.base_stats = Stats.new()
	pc.weapon = Weapon.new()   # non-null, so an un-guarded _compare_lines() would wrongly compare a
	                           # selected potion against it (see the _compare_lines guard fix below)
	pc.weapon.display_name = "Test Sword"

	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = _make_potion(30, 3)
	inv.items = [potion]
	var vault: Vault = Vault.new()

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault)
	panel.switch_tab_for_test(&"bag")

	_check(panel.combined_items([], [], [potion]) == ([{"item": potion, "is_weapon": false}] as Array[Dictionary]), "combined_items() includes a passed item_list")

	var found_button: Button = null
	for child in panel.get_children():
		if child is Button and (child as Button).text.begins_with("Healing Potion"):
			found_button = child
	_check(found_button != null, "the Bag grid renders a button for the owned potion")
	_check(found_button.text == "Healing Potion x3", "the potion's grid button shows name and quantity")
	_check(found_button.tooltip_text.find("Heals your target for 30 HP") != -1, "the potion's tooltip states its effect (got '%s')" % found_button.tooltip_text)
	_check(found_button.tooltip_text.find("vs ") == -1, "a Consumable's tooltip has no bogus Gear/Weapon compare line (got '%s')" % found_button.tooltip_text)

	# 2026-07-26 self-review fix: before this task, a ConsumableItem could never reach _selected/
	# _equip_selected/_auto_equip_onto_pc at all (nothing rendered it in the grid). Making it
	# grid-selectable exposed a latent `(item as Gear).slot` crash in both the explicit-slot-click
	# equip path and the double-click auto-equip path — fixed by guarding both to no-op on a
	# non-Gear/Weapon selection. Confirm both paths are now silent no-ops, not crashes.
	panel.select_grid_item_for_test(potion, false)
	panel.press_slot_for_test(1, 1)   # PC column, Headwear slot
	_check(inv.items.size() == 1 and inv.items[0] == potion, "explicit slot-click on a selected potion does not remove it from the Bag")
	_check(pc.gear.is_empty(), "explicit slot-click on a selected potion does not equip anything")

	panel.double_click_grid_item_for_test(potion, false)
	_check(inv.items.size() == 1 and inv.items[0] == potion, "double-clicking a potion does not remove it from the Bag")
	_check(pc.gear.is_empty(), "double-clicking a potion does not equip anything")

	panel.free()
	quit()
