extends SceneTree

## Headless test: equipping gear through InventoryMenuPanel completes the tutorial's equip_gear
## objective (2026-08-10 quest-popups-and-tutorial-wiring plan Task 10). The open_inventory half of
## this task is covered by the 3 scene-level tests in this same task's Step 1 addendum below.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()
	inv.accept_quest(&"tutorial")
	var pc := Combatant.new()
	pc.is_player = true
	var gear := Gear.new()
	gear.display_name = "Test Helm"
	gear.slot = Gear.Slot.HEADWEAR
	inv.give_gear(gear)

	var panel := InventoryMenuPanel.new()
	var vault := Vault.new()
	panel.open_for(pc, [], inv, vault, true)
	_check(not inv.is_objective_complete(&"tutorial", &"equip_gear"), "equip_gear isn't complete before any equip happens")

	panel.select_item_for_test(gear, false)
	panel.equip_selected_for_test(pc, panel.gear_slot_index_for(gear.slot))
	_check(inv.is_objective_complete(&"tutorial", &"equip_gear"), "equipping a piece of Gear completes the tutorial's equip_gear objective")

	panel.free()
	print(("INVENTORY MENU PANEL TUTORIAL OBJECTIVES TEST PASSED" if _failures == 0 else "INVENTORY MENU PANEL TUTORIAL OBJECTIVES TEST FAILED: %d" % _failures))
	quit(_failures)
