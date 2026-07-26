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

	panel.free()
	quit()
