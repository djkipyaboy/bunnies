extends SceneTree

## View-layer smoke: InventoryMenuPanel's paperdoll display — 3 columns (Companion1 | PC | Companion2),
## dim placeholder for a missing companion, slot labels reflecting equipped items vs "— empty —".

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.base_stats = Stats.new()
	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.display_name = "Cloth Cap"
	hat.stat_bonuses = Stats.new()
	pc.gear = [hat]
	var sword: Weapon = Weapon.new()
	sword.display_name = "Shortsword"
	pc.weapon = sword

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()

	var columns: Array = InventoryMenuPanel.paperdoll_columns(pc, [])
	_check(columns[0] == null and columns[2] == null, "no companions -> both companion columns null")
	_check(columns[1] == pc, "PC is always the center column")

	_check(InventoryMenuPanel.equipped_item(pc, 0) == sword, "slot 0 (Weapon) reads Combatant.weapon")
	_check(InventoryMenuPanel.equipped_item(pc, 1) == hat, "slot 1 (Headwear) reads the matching Gear")
	_check(InventoryMenuPanel.equipped_item(pc, 2) == null, "an empty slot reads null")
	_check(InventoryMenuPanel.slot_display_text(null) == "— empty —", "empty slot displays em-dash placeholder")
	_check(InventoryMenuPanel.slot_display_text(hat) == "Cloth Cap", "equipped Gear displays its name")

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.slot_button_text_for_test(1, 1) == "Headwear: Cloth Cap", "PC column headwear slot shows the equipped item")
	_check(panel.slot_button_text_for_test(0, 1).contains("no companion"), "companion column with no companion shows the placeholder")

	panel.free()
	quit()
