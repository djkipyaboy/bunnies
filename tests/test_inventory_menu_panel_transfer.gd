extends SceneTree

## View-layer test: click-to-select-then-click-target equip/unequip and Bag<->Vault transfer
## (spec §3.2), plus the 2026-07-11 UX additions: container-agnostic equip (Vault items are now
## directly equippable), clicked-box targeting (Charm has two boxes), valid-target highlighting,
## and double-click auto-equip/auto-withdraw (spec 2026-07-11-inventory-ux-additions-design.md).

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
	_check(panel.equip_reject_message_for_test() == "Requires level 7", "a rejected equip shows a level-requirement message")
	pc.level = 9

	# Selecting a different item clears a stale rejection message.
	panel.select_grid_item_for_test(hat, false)
	_check(panel.equip_reject_message_for_test() == "", "selecting a new item clears the equip-rejection message")

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

	# Vault items are now DIRECTLY equippable (spec §3.2, updated 2026-07-11 — the old
	# "must withdraw to Bag first" restriction is removed). Equipping from the Vault tab takes
	# from and displaces into the Vault, not the Bag. Uses fresh items (not `hat`) so the later
	# "Vault -> Bag" test below, which still exercises `hat`, is unaffected.
	panel.switch_tab_for_test(&"vault")
	var vault_gloves: Gear = Gear.new()
	vault_gloves.slot = Gear.Slot.HANDS
	vault_gloves.display_name = "Vault Gloves"
	vault_gloves.stat_bonuses = Stats.new()
	vault.gear.append(vault_gloves)
	panel.select_grid_item_for_test(vault_gloves, false)
	panel.press_slot_for_test(1, 4)
	_check(pc.gear.has(vault_gloves), "selecting a Vault item then clicking a matching paperdoll slot equips it")
	_check(not vault.gear.has(vault_gloves), "the equipped item leaves the Vault, not just gets duplicated")
	_check(not inv.gear.has(vault_gloves), "the item equipped from the Vault does NOT land in the Bag")

	var vault_gloves_2: Gear = Gear.new()
	vault_gloves_2.slot = Gear.Slot.HANDS
	vault_gloves_2.display_name = "Vault Gloves 2"
	vault_gloves_2.stat_bonuses = Stats.new()
	vault.gear.append(vault_gloves_2)
	panel.select_grid_item_for_test(vault_gloves_2, false)
	panel.press_slot_for_test(1, 4)
	_check(pc.gear.has(vault_gloves_2) and not pc.gear.has(vault_gloves), "equipping a second Vault item into the same slot displaces the first")
	_check(vault.gear.has(vault_gloves) and not vault.gear.has(vault_gloves_2), "the displaced item returns to the Vault, not the Bag")
	_check(not inv.gear.has(vault_gloves), "the displaced Vault item does NOT land in the Bag")

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

	# Unequip: nothing selected, click the occupied weapon slot. Combatant.unequip_weapon() falls
	# back to a real (unarmed) Weapon rather than leaving pc.weapon actually null (2026-07-12 fix —
	# a combatant with no weapon equipped had zero action reels) — the real displaced weapon still
	# returns to the bag correctly, and the unarmed fallback itself never does.
	panel.press_slot_for_test(1, 0)
	_check(pc.weapon != null and pc.weapon.is_unarmed, "clicking the occupied weapon slot with nothing selected unequips it, falling back to Unarmed Strike")
	_check(inv.weapons.has(new_weapon), "the unequipped weapon returns to the bag")
	_check(not inv.weapons.any(func(w: Weapon) -> bool: return w.is_unarmed), "the unarmed fallback itself is never added to the bag")

	# Weapon Bag -> Vault -> Bag.
	vault.tab_capacity[&"weapons"] = 1
	panel.select_grid_item_for_test(new_weapon, true)
	panel.press_send_to_vault_for_test()
	_check(vault.weapons.has(new_weapon) and not inv.weapons.has(new_weapon), "Send to Vault moves a weapon from bag to Vault")

	panel.switch_tab_for_test(&"vault")
	panel.select_grid_item_for_test(new_weapon, true)
	panel.press_withdraw_for_test()
	_check(inv.weapons.has(new_weapon) and not vault.weapons.has(new_weapon), "Withdraw to Bag moves a weapon from Vault to bag")

	# --- Explicit paperdoll clicks target the box that was actually clicked (spec §2), not the
	# item's original .slot — a prerequisite made user-visible now that Charm has two boxes. A
	# Charm authored generically as CHARM, clicked onto the CHARM_2 box (slot_idx 6), must land
	# there and get pinned (.slot reassigned) to CHARM_2. ---
	panel.switch_tab_for_test(&"bag")
	var charm_a: Gear = Gear.new()
	charm_a.slot = Gear.Slot.CHARM
	charm_a.display_name = "Lucky Coin"
	charm_a.stat_bonuses = Stats.new()
	inv.gear.append(charm_a)
	panel.select_grid_item_for_test(charm_a, false)
	panel.press_slot_for_test(1, 6)
	_check(InventoryMenuPanel.equipped_item(pc, 6) == charm_a, "clicking the CHARM_2 box equips the item there, not wherever its original .slot pointed")
	_check(InventoryMenuPanel.equipped_item(pc, 5) == null, "the CHARM box (slot 5) stays empty — the item did not land on its original .slot")
	_check(charm_a.slot == Gear.Slot.CHARM_2, "the item's .slot is reassigned to match the box actually clicked")

	# --- Reopen reset: open_for() must reset to the Bag tab with no stale selection, even if the
	# panel was left on the Vault tab with an item selected (the panel is a long-lived instance
	# toggled via hide()/open_for(), never recreated). ---
	panel.switch_tab_for_test(&"vault")
	panel.select_grid_item_for_test(hat, false)
	_check(panel.active_tab_for_test() == &"vault", "sanity: the panel is on the Vault tab before reopening")
	panel.open_for(pc, [], inv, vault)
	_check(panel.active_tab_for_test() == &"bag", "reopening the panel resets to the default Bag tab")

	panel.free()

	# --- is_valid_target (spec §3.1): pure static-helper coverage. ---
	var weapon_item: Weapon = Weapon.new()
	_check(InventoryMenuPanel.is_valid_target(weapon_item, true, 0), "a weapon is a valid target at slot_idx 0")
	_check(not InventoryMenuPanel.is_valid_target(weapon_item, true, 3), "a weapon is not a valid target at any other slot_idx")

	var chest_item: Gear = Gear.new()
	chest_item.slot = Gear.Slot.CHEST
	_check(InventoryMenuPanel.is_valid_target(chest_item, false, 3), "a Chest item is a valid target at its one Chest box (slot_idx 3)")
	_check(not InventoryMenuPanel.is_valid_target(chest_item, false, 1), "a Chest item is not a valid target at Headwear")
	_check(not InventoryMenuPanel.is_valid_target(chest_item, false, 0), "a Chest item is not a valid target at the Weapon box")

	var charm_item_a: Gear = Gear.new()
	charm_item_a.slot = Gear.Slot.CHARM
	_check(InventoryMenuPanel.is_valid_target(charm_item_a, false, 5), "a Charm item (.slot == CHARM) is a valid target at the CHARM box")
	_check(InventoryMenuPanel.is_valid_target(charm_item_a, false, 6), "a Charm item (.slot == CHARM) is ALSO a valid target at the CHARM_2 box")
	_check(not InventoryMenuPanel.is_valid_target(charm_item_a, false, 3), "a Charm item is not a valid target at Chest")

	var charm_item_b: Gear = Gear.new()
	charm_item_b.slot = Gear.Slot.CHARM_2
	_check(InventoryMenuPanel.is_valid_target(charm_item_b, false, 5), "a Charm item (.slot == CHARM_2) is ALSO a valid target at the CHARM box")
	_check(InventoryMenuPanel.is_valid_target(charm_item_b, false, 6), "a Charm item (.slot == CHARM_2) is a valid target at the CHARM_2 box")
	_check(not InventoryMenuPanel.is_valid_target(charm_item_b, false, 1), "a Charm item is not a valid target at Headwear")

	_check(not InventoryMenuPanel.is_valid_target(null, false, 1), "a null selection is never a valid target")

	# --- Double-click auto-equip/auto-withdraw (spec §3.3, §3.4, §3.5). Isolated Combatant/
	# PartyInventory/Vault/Panel so this section doesn't inherit the mutated state above. ---
	var dc_pc: Combatant = Combatant.new()
	dc_pc.level = 9
	dc_pc.base_stats = Stats.new()
	var dc_inv: PartyInventory = PartyInventory.new()
	var dc_vault: Vault = Vault.new()
	dc_vault.tab_capacity[&"gear"] = 10
	dc_vault.tab_capacity[&"weapons"] = 10
	var dc_panel: InventoryMenuPanel = InventoryMenuPanel.new()
	dc_panel.open_for(dc_pc, [], dc_inv, dc_vault)

	# Bag weapon double-click equips onto the PC.
	var dc_weapon: Weapon = Weapon.new()
	dc_weapon.display_name = "Bag Sword"
	dc_inv.weapons.append(dc_weapon)
	dc_panel.double_click_grid_item_for_test(dc_weapon, true)
	_check(dc_pc.weapon == dc_weapon, "double-clicking a Bag weapon equips it onto the PC")
	_check(not dc_inv.weapons.has(dc_weapon), "the equipped weapon leaves the Bag")

	# Bag Charm double-click, one empty Charm slot -> fills CHARM first.
	var dc_charm_1: Gear = Gear.new()
	dc_charm_1.slot = Gear.Slot.CHARM
	dc_charm_1.display_name = "Charm One"
	dc_charm_1.rarity = RarityVisuals.Rarity.UNCOMMON
	dc_charm_1.stat_bonuses = Stats.new()
	dc_inv.gear.append(dc_charm_1)
	dc_panel.double_click_grid_item_for_test(dc_charm_1, false)
	_check(InventoryMenuPanel.equipped_item(dc_pc, 5) == dc_charm_1, "double-clicking a Bag Charm with an empty Charm slot fills CHARM")
	_check(dc_charm_1.slot == Gear.Slot.CHARM, "the auto-placed charm is pinned to the CHARM slot")

	# Fill the second Charm slot too, so the next double-click sees both slots occupied.
	var dc_charm_2: Gear = Gear.new()
	dc_charm_2.slot = Gear.Slot.CHARM
	dc_charm_2.display_name = "Charm Two"
	dc_charm_2.rarity = RarityVisuals.Rarity.EPIC
	dc_charm_2.stat_bonuses = Stats.new()
	dc_inv.gear.append(dc_charm_2)
	dc_panel.double_click_grid_item_for_test(dc_charm_2, false)
	_check(InventoryMenuPanel.equipped_item(dc_pc, 6) == dc_charm_2, "with CHARM already filled, the next double-clicked Charm fills the empty CHARM_2")

	# Both Charm slots filled at different rarities (CHARM = Uncommon, CHARM_2 = Epic) ->
	# double-clicking a new Charm replaces the LOWER-rarity one (CHARM here).
	var dc_charm_3: Gear = Gear.new()
	dc_charm_3.slot = Gear.Slot.CHARM
	dc_charm_3.display_name = "Charm Three"
	dc_charm_3.rarity = RarityVisuals.Rarity.COMMON
	dc_charm_3.stat_bonuses = Stats.new()
	dc_inv.gear.append(dc_charm_3)
	dc_panel.double_click_grid_item_for_test(dc_charm_3, false)
	_check(InventoryMenuPanel.equipped_item(dc_pc, 5) == dc_charm_3, "with both Charm slots filled at different rarities, double-click replaces the lower-rarity one")
	_check(InventoryMenuPanel.equipped_item(dc_pc, 6) == dc_charm_2, "the higher-rarity Charm (CHARM_2) is left untouched")
	_check(dc_inv.gear.has(dc_charm_1) and not dc_pc.gear.has(dc_charm_1), "the replaced (lower-rarity) charm is displaced back to the Bag")

	# Both Charm slots filled at EQUAL rarity -> tie-break defaults to replacing CHARM (slot 1).
	# Fresh Combatant/inventory so slot occupancy is unambiguous.
	var tie_pc: Combatant = Combatant.new()
	tie_pc.level = 9
	tie_pc.base_stats = Stats.new()
	var tie_inv: PartyInventory = PartyInventory.new()
	var tie_vault: Vault = Vault.new()
	var tie_panel: InventoryMenuPanel = InventoryMenuPanel.new()
	tie_panel.open_for(tie_pc, [], tie_inv, tie_vault)

	var tie_charm_1: Gear = Gear.new()
	tie_charm_1.slot = Gear.Slot.CHARM
	tie_charm_1.display_name = "Tie Charm One"
	tie_charm_1.rarity = RarityVisuals.Rarity.RARE
	tie_charm_1.stat_bonuses = Stats.new()
	tie_inv.gear.append(tie_charm_1)
	tie_panel.double_click_grid_item_for_test(tie_charm_1, false)

	var tie_charm_2: Gear = Gear.new()
	tie_charm_2.slot = Gear.Slot.CHARM
	tie_charm_2.display_name = "Tie Charm Two"
	tie_charm_2.rarity = RarityVisuals.Rarity.RARE
	tie_charm_2.stat_bonuses = Stats.new()
	tie_inv.gear.append(tie_charm_2)
	tie_panel.double_click_grid_item_for_test(tie_charm_2, false)
	_check(InventoryMenuPanel.equipped_item(tie_pc, 5) == tie_charm_1 and InventoryMenuPanel.equipped_item(tie_pc, 6) == tie_charm_2, "sanity: both Charm slots filled at equal (Rare) rarity")

	var tie_charm_3: Gear = Gear.new()
	tie_charm_3.slot = Gear.Slot.CHARM
	tie_charm_3.display_name = "Tie Charm Three"
	tie_charm_3.rarity = RarityVisuals.Rarity.RARE
	tie_charm_3.stat_bonuses = Stats.new()
	tie_inv.gear.append(tie_charm_3)
	tie_panel.double_click_grid_item_for_test(tie_charm_3, false)
	_check(InventoryMenuPanel.equipped_item(tie_pc, 5) == tie_charm_3, "an equal-rarity tie defaults to replacing CHARM (slot 1)")
	_check(InventoryMenuPanel.equipped_item(tie_pc, 6) == tie_charm_2, "CHARM_2 is left untouched by the tie-break")
	_check(tie_inv.gear.has(tie_charm_1), "the tie-broken-out charm (CHARM) is displaced back to the Bag")
	tie_panel.free()

	# A too-high-level Bag item shows the "Requires level N" message on the double-click path too,
	# and does not equip.
	var dc_epic: Gear = Gear.new()
	dc_epic.slot = Gear.Slot.CHEST
	dc_epic.display_name = "Overlevel Plate"
	dc_epic.rarity = RarityVisuals.Rarity.EPIC
	dc_epic.stat_bonuses = Stats.new()
	dc_inv.gear.append(dc_epic)
	dc_pc.level = 1
	dc_panel.double_click_grid_item_for_test(dc_epic, false)
	_check(not dc_pc.gear.has(dc_epic), "a too-high-level Bag item does not get equipped by double-click")
	_check(dc_inv.gear.has(dc_epic), "a rejected double-click equip leaves the item in the Bag")
	_check(dc_panel.equip_reject_message_for_test() == "Requires level 7", "double-click auto-equip shows the same 'Requires level N' message as an explicit slot-click")
	dc_pc.level = 9

	# Vault tab double-click auto-withdraws to the Bag — it does NOT auto-equip anywhere.
	dc_panel.switch_tab_for_test(&"vault")
	var dc_vault_item: Gear = Gear.new()
	dc_vault_item.slot = Gear.Slot.CLOAK
	dc_vault_item.display_name = "Vault Cloak"
	dc_vault_item.stat_bonuses = Stats.new()
	dc_vault.gear.append(dc_vault_item)
	dc_panel.double_click_grid_item_for_test(dc_vault_item, false)
	_check(dc_inv.gear.has(dc_vault_item) and not dc_vault.gear.has(dc_vault_item), "double-clicking a Vault item withdraws it to the Bag")
	_check(not dc_pc.gear.has(dc_vault_item), "double-clicking a Vault item does not equip it anywhere")

	dc_panel.free()

	# --- Vault-unavailable (not a safe zone, e.g. the overworld map): open_for's 5th param gates
	# the Vault tab. Bag/equip stay fully usable; the Vault tab is still clickable but shows the
	# unavailable message instead of contents, and the Bag tab's "Send to Vault" action is hidden
	# too (the Vault is unreachable in either direction). ---
	var nz_pc: Combatant = Combatant.new()
	nz_pc.level = 9
	nz_pc.base_stats = Stats.new()
	var nz_inv: PartyInventory = PartyInventory.new()
	var nz_boots: Gear = Gear.new()
	nz_boots.slot = Gear.Slot.HANDS
	nz_boots.display_name = "Field Gloves"
	nz_boots.stat_bonuses = Stats.new()
	nz_inv.gear = [nz_boots]
	var nz_vault: Vault = Vault.new()
	var nz_vault_item: Gear = Gear.new()
	nz_vault_item.slot = Gear.Slot.CHEST
	nz_vault_item.stat_bonuses = Stats.new()
	nz_vault.gear = [nz_vault_item]

	var nz_panel: InventoryMenuPanel = InventoryMenuPanel.new()
	nz_panel.open_for(nz_pc, [], nz_inv, nz_vault, false)
	_check(not nz_panel.vault_unavailable_message_shown_for_test(), "the Bag tab (default) shows no Vault-unavailable message")

	# Bag/equip still fully work outside a safe zone.
	nz_panel.select_grid_item_for_test(nz_boots, false)
	nz_panel.press_slot_for_test(1, 4)
	_check(nz_pc.gear.has(nz_boots), "equipping from the Bag still works when the Vault is unavailable")

	nz_panel.switch_tab_for_test(&"vault")
	_check(nz_panel.vault_unavailable_message_shown_for_test(), "switching to the Vault tab shows the unavailable message")
	_check(nz_panel.active_tab_for_test() == &"vault", "the Vault tab is still selectable/viewable, just empty")

	# The Vault's real contents must not leak into the (empty) grid while unavailable, and can't be
	# selected/equipped/withdrawn.
	nz_panel.select_grid_item_for_test(nz_vault_item, false)
	nz_panel.press_slot_for_test(1, 3)
	_check(not nz_pc.gear.has(nz_vault_item), "a Vault item cannot be equipped while the Vault is unavailable (its grid renders no items to select)")
	_check(nz_vault.gear.has(nz_vault_item), "the Vault's contents are untouched while unavailable")

	nz_panel.free()

	# --- Materials tab selection (2026-07-14 ground-item-pickups) ---
	var mat_inv: PartyInventory = PartyInventory.new()
	var ore: CraftingMaterial = CraftingMaterial.new()
	ore.material_type = &"iron_ore"
	ore.display_name = "Iron Ore"
	ore.quantity = 4
	mat_inv.materials = [ore]
	var mat_pc: Combatant = Combatant.new()
	mat_pc.level = 9
	mat_pc.base_stats = Stats.new()
	var mat_vault: Vault = Vault.new()
	var mat_panel: InventoryMenuPanel = InventoryMenuPanel.new()
	mat_panel.open_for(mat_pc, [], mat_inv, mat_vault)
	mat_panel.switch_tab_for_test(&"materials")

	mat_panel.select_material_for_test(ore)
	_check(mat_panel.list_row_text_for_test(0).find("✓") != -1, "selecting a material shows a checkmark on its row")

	# Selecting a Gear item elsewhere clears the material selection (mutual exclusion).
	var mat_gear: Gear = Gear.new()
	mat_gear.display_name = "Some Gear"
	mat_inv.gear = [mat_gear]
	mat_panel.switch_tab_for_test(&"bag")
	mat_panel.select_grid_item_for_test(mat_gear, false)
	mat_panel.switch_tab_for_test(&"materials")
	_check(mat_panel.list_row_text_for_test(0).find("✓") == -1, "selecting a Gear item elsewhere clears the material selection")

	mat_panel.free()

	quit()
