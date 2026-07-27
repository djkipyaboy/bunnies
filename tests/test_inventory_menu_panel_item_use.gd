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

	# Action row: Send to Vault only for Gear/Weapon, Use only for a selected Consumable.
	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.display_name = "Cloth Cap"
	hat.stat_bonuses = Stats.new()
	inv.gear = [hat]
	panel._rebuild()

	panel.select_grid_item_for_test(hat, false)
	_check(panel._action_button != null and panel._action_button.text == "Send to Vault", "selecting Gear shows Send to Vault")
	_check(not panel.use_button_visible_for_test(), "selecting Gear does not show a Use button")

	panel.select_grid_item_for_test(potion, false)
	_check(panel._action_button == null, "selecting a Consumable hides Send to Vault (no Vault storage exists for it)")
	_check(panel.use_button_visible_for_test(), "selecting a Consumable shows a Use button")

	# Targeting flow: press Use, click a column, Confirm applies + consumes; Cancel doesn't.
	var companion: Combatant = Combatant.new()
	companion.display_name = "Basil"
	companion.max_hp = 100
	companion.hp = 40
	panel._companions = [companion]
	pc.max_hp = 100
	pc.hp = 100
	panel._rebuild()

	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	_check(panel.active_tab_for_test() == &"stats", "pressing Use switches to the Stats tab")
	_check(panel.use_pending_item_for_test() == potion, "pressing Use arms the pending item")
	_check(panel.use_confirm_disabled_for_test(), "Confirm is disabled before a target is picked")
	_check(not panel.use_click_catcher_exists_for_test(2), "the empty 3rd companion column has no click-catcher")
	_check(panel.use_click_catcher_exists_for_test(1), "the PC's own column has a click-catcher")

	panel.click_use_target_for_test(0)  # column 0 = Companion 1 = Basil
	_check(panel.use_target_for_test() == companion, "clicking a column sets it as the target")
	_check(not panel.use_confirm_disabled_for_test(), "Confirm is enabled once a target is picked")
	_check(panel.use_description_text_for_test().find("Basil") != -1, "the live description names the current target (got '%s')" % panel.use_description_text_for_test())

	panel.press_use_confirm_for_test()
	_check(companion.hp == 70, "Confirm applies the heal to the targeted ally")
	_check(inv.find_item(&"healing_potion").quantity == 2, "Confirm consumes exactly 1 unit")
	_check(panel.use_pending_item_for_test() == null, "Confirm exits targeting mode")
	_check(panel.use_result_message_for_test().find("Basil") != -1, "the result message names the healed ally (got '%s')" % panel.use_result_message_for_test())

	# Cancel: no consumption, no effect.
	# 2026-07-26 reviewer fix: _on_use_pressed() leaves _active_tab == "stats" (Confirm above never
	# switches it back), and the Use button only exists on the Bag tab (_build_action_row() is only
	# called from _rebuild()'s non-stats branch) — without switching back to Bag first,
	# press_use_for_test() would silently no-op (no button to press) and every check below would
	# pass vacuously on already-true leftover state, never actually exercising Cancel.
	panel.switch_tab_for_test(&"bag")
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.click_use_target_for_test(0)
	panel.press_use_cancel_for_test()
	_check(companion.hp == 70, "Cancel does not apply the effect")
	_check(inv.find_item(&"healing_potion").quantity == 2, "Cancel does not consume a unit")
	_check(panel.use_pending_item_for_test() == null, "Cancel exits targeting mode")

	# Switching tabs while armed cancels targeting the same way.
	# Same reason as the Cancel block above: Cancel left _active_tab == "stats", so the Use button
	# needs the Bag tab re-armed first before press_use_for_test() has anything to press.
	panel.switch_tab_for_test(&"bag")
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.switch_tab_for_test(&"bag")
	_check(panel.use_pending_item_for_test() == null, "switching tabs while armed cancels targeting")
	_check(inv.find_item(&"healing_potion").quantity == 2, "switching tabs while armed does not consume a unit")

	# Targeting column 1 (the PC's own column, not just the companion column tested above).
	pc.hp = 60   # give the PC missing HP so a heal is actually observable
	panel.switch_tab_for_test(&"bag")
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.click_use_target_for_test(1)  # column 1 = PC
	_check(panel.use_target_for_test() == pc, "clicking column 1 targets the PC")
	panel.press_use_confirm_for_test()
	_check(pc.hp == 90, "Confirm applies the heal to the PC when targeted via column 1")
	_check(inv.find_item(&"healing_potion").quantity == 1, "Confirm on the PC-column target still consumes exactly 1 unit")

	# Reopening the panel clears any stale armed state.
	panel.switch_tab_for_test(&"bag")
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.click_use_target_for_test(0)
	_check(panel.use_target_for_test() == companion, "sanity: armed with a target before reopen")
	panel.open_for(pc, [companion], inv, vault)
	_check(panel.use_pending_item_for_test() == null, "open_for() clears a stale pending item")
	_check(panel.use_target_for_test() == null, "open_for() clears a stale target")

	# No-effect warning (2026-07-26 design): a full-HP or dead target shows a warning and keeps
	# Confirm disabled instead of applying a wasted use.
	companion.hp = companion.max_hp   # full HP
	potion.quantity = 3               # earlier sections in this file consumed this stack down;
	inv.items = [potion]              # reset both the quantity and the array entry so this section
	                                   # is self-contained regardless of how much was consumed above
	panel._rebuild()
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.click_use_target_for_test(0)
	_check(panel.use_confirm_disabled_for_test(), "Confirm stays disabled when the target is already at full HP")
	_check(panel.use_description_text_for_test().find("no effect") != -1, "the description warns of no effect on a full-HP target (got '%s')" % panel.use_description_text_for_test())
	panel.press_use_confirm_for_test()   # no-op: hook itself checks disabled
	_check(companion.hp == companion.max_hp, "a disabled Confirm cannot be pressed into applying a wasted heal")
	_check(panel.use_pending_item_for_test() == potion, "a disabled Confirm does not exit targeting mode")

	companion.hp = 0   # dead
	panel.click_use_target_for_test(0)
	_check(panel.use_confirm_disabled_for_test(), "Confirm stays disabled when the target is dead")
	_check(panel.use_description_text_for_test().find("no effect") != -1, "the description warns of no effect on a dead target (got '%s')" % panel.use_description_text_for_test())
	panel.press_use_cancel_for_test()

	panel.free()
	quit()
