extends SceneTree

## View-layer test: click-to-select-then-click-target equip/unequip and Bag<->Vault transfer
## (spec §3.2), driven via _for_test() hooks (no real mouse events).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.level = 9
	pc.base_stats = Stats.new()

	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.display_name = "Old Cap"
	hat.stat_bonuses = Stats.new()
	pc.gear = [hat]

	var new_hat: Gear = Gear.new()
	new_hat.slot = Gear.Slot.HEADWEAR
	new_hat.display_name = "New Cap"
	new_hat.stat_bonuses = Stats.new()

	var inv: PartyInventory = PartyInventory.new()
	inv.gear = [new_hat]
	var vault: Vault = Vault.new()
	vault.tab_capacity[&"gear"] = 1

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault)

	# Equip: select the bag item, then click the PC's headwear slot (column 1, slot 1).
	panel.select_grid_item_for_test(new_hat, false)
	panel.press_slot_for_test(1, 1)
	_check(pc.gear.has(new_hat) and not pc.gear.has(hat), "selecting a bag item then clicking a slot equips it, displacing the old one")
	_check(inv.gear.has(hat) and not inv.gear.has(new_hat), "the displaced item returns to the bag; the equipped one leaves it")

	# Unequip: nothing selected, click an occupied slot.
	panel.press_slot_for_test(1, 1)
	_check(not pc.gear.has(new_hat), "clicking an occupied slot with nothing selected unequips it")
	_check(inv.gear.has(new_hat), "the unequipped item returns to the bag")

	# A rejected equip (level-gate) leaves both sides untouched.
	var epic: Gear = Gear.new()
	epic.slot = Gear.Slot.CHEST
	epic.rarity = RarityVisuals.Rarity.EPIC
	epic.stat_bonuses = Stats.new()
	inv.gear.append(epic)
	pc.level = 1
	panel.select_grid_item_for_test(epic, false)
	panel.press_slot_for_test(1, 3)
	_check(not pc.gear.has(epic), "a rejected equip (level-gate) does not equip")
	_check(inv.gear.has(epic), "a rejected equip leaves the item in the bag")
	pc.level = 9

	# Bag -> Vault.
	panel.select_grid_item_for_test(hat, false)
	panel.press_send_to_vault_for_test()
	_check(vault.gear.has(hat) and not inv.gear.has(hat), "Send to Vault moves the item from bag to Vault")

	# Vault full.
	var overflow: Gear = Gear.new()
	overflow.slot = Gear.Slot.CHARM
	overflow.stat_bonuses = Stats.new()
	inv.gear.append(overflow)
	panel.select_grid_item_for_test(overflow, false)
	panel.press_send_to_vault_for_test()
	_check(not vault.gear.has(overflow), "deposit is refused once the Vault gear tab is at capacity")
	_check(panel.vault_full_message_shown_for_test(), "a refused deposit shows the Vault-full message")
	_check(inv.gear.has(overflow), "a refused deposit leaves the item in the bag")

	# Vault items are not directly equippable (spec §3.2): selecting one and clicking a
	# paperdoll slot must no-op, not equip-and-duplicate.
	panel.switch_tab_for_test(&"vault")
	panel.select_grid_item_for_test(hat, false)
	panel.press_slot_for_test(1, 1)
	_check(vault.gear.has(hat), "a Vault item selected while the Vault tab is active is not equipped and stays in the Vault")
	_check(not pc.gear.has(hat), "clicking a paperdoll slot with a Vault item selected does not equip it onto the PC")

	# Vault -> Bag.
	panel.switch_tab_for_test(&"vault")
	panel.select_grid_item_for_test(hat, false)
	panel.press_withdraw_for_test()
	_check(inv.gear.has(hat) and not vault.gear.has(hat), "Withdraw to Bag moves the item from Vault to bag")

	# --- Weapon path: the panel's own orchestration of equip/unequip/deposit/withdraw for the
	# Weapon slot (slot 0), mirroring the Gear-path coverage above. ---
	panel.switch_tab_for_test(&"bag")

	var old_weapon: Weapon = Weapon.new()
	old_weapon.display_name = "Old Sword"
	pc.weapon = old_weapon

	var new_weapon: Weapon = Weapon.new()
	new_weapon.display_name = "New Sword"
	inv.weapons = [new_weapon]

	# Equip: select the bag weapon, then click the PC's weapon slot (column 1, slot 0).
	panel.select_grid_item_for_test(new_weapon, true)
	panel.press_slot_for_test(1, 0)
	_check(pc.weapon == new_weapon, "selecting a bag weapon then clicking the weapon slot equips it")
	_check(inv.weapons.has(old_weapon), "the displaced weapon returns to the bag")
	_check(not inv.weapons.has(new_weapon), "the equipped weapon leaves the bag")

	# Unequip: nothing selected, click the occupied weapon slot.
	panel.press_slot_for_test(1, 0)
	_check(pc.weapon == null, "clicking the occupied weapon slot with nothing selected unequips it")
	_check(inv.weapons.has(new_weapon), "the unequipped weapon returns to the bag")

	# Weapon Bag -> Vault -> Bag.
	vault.tab_capacity[&"weapons"] = 1
	panel.select_grid_item_for_test(new_weapon, true)
	panel.press_send_to_vault_for_test()
	_check(vault.weapons.has(new_weapon) and not inv.weapons.has(new_weapon), "Send to Vault moves a weapon from bag to Vault")

	panel.switch_tab_for_test(&"vault")
	panel.select_grid_item_for_test(new_weapon, true)
	panel.press_withdraw_for_test()
	_check(inv.weapons.has(new_weapon) and not vault.weapons.has(new_weapon), "Withdraw to Bag moves a weapon from Vault to bag")

	# --- Reopen reset: open_for() must reset to the Bag tab with no stale selection, even if the
	# panel was left on the Vault tab with an item selected (the panel is a long-lived instance
	# toggled via hide()/open_for(), never recreated). ---
	panel.switch_tab_for_test(&"vault")
	panel.select_grid_item_for_test(hat, false)
	_check(panel.active_tab_for_test() == &"vault", "sanity: the panel is on the Vault tab before reopening")
	panel.open_for(pc, [], inv, vault)
	_check(panel.active_tab_for_test() == &"bag", "reopening the panel resets to the default Bag tab")

	panel.free()
	quit()
