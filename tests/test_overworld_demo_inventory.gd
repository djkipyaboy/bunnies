extends SceneTree

## Headless smoke test: the equipment/inventory UI is wired into the overworld demo the same way
## it's wired into town_demo (I-key toggle opens/closes InventoryMenuPanel, pauses/resumes PC
## movement, blocks `interact` while open) — but the overworld is NOT a safe zone, so its Vault tab
## must render the "Travel to the nearest settlement to access" message instead of vault contents
## (2026-07-11 follow-up to the inventory-ux-additions spec).

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var overworld: OverworldDemo = _instance
		_check(overworld._inventory_panel != null, "InventoryMenuPanel is built")
		_check(not overworld._inventory_panel.visible, "InventoryMenuPanel starts hidden")
		overworld._toggle_inventory()
		_check(overworld._inventory_panel.visible, "toggle opens the panel")
		_check(overworld._pc.movement_paused_for_test(), "toggle pauses PC movement")

		# interact must not fire while the inventory panel is open.
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		overworld._unhandled_input(interact_event)   # should no-op; nothing to assert beyond "doesn't crash"

		# The overworld is not a safe zone: Bag stays fully usable, but switching to the Vault tab
		# shows the unavailable message instead of vault contents.
		_check(overworld._inventory_panel.active_tab_for_test() == &"bag", "panel opens on the Bag tab by default")
		_check(not overworld._inventory_panel.vault_unavailable_message_shown_for_test(), "Bag tab shows no Vault-unavailable message")
		overworld._inventory_panel.switch_tab_for_test(&"vault")
		_check(overworld._inventory_panel.vault_unavailable_message_shown_for_test(), "Vault tab on the overworld shows the Vault-unavailable message")

		# Manual Discard spawns a real GroundItemPickup at the PC's position
		# (2026-07-14-ground-item-pickups-design.md §3.7).
		overworld._inventory_panel.switch_tab_for_test(&"bag")
		var junk: Gear = Gear.new()
		junk.display_name = "Discard Test Item"
		overworld._party_inventory.gear.append(junk)
		overworld._inventory_panel._rebuild()
		overworld._inventory_panel.select_grid_item_for_test(junk, false)
		overworld._inventory_panel.press_discard_for_test()
		overworld._inventory_panel.confirm_discard_for_test()
		var found_pickup: bool = false
		for child in overworld._world.get_children():
			if child is GroundItemPickup and (child.item as Gear).display_name == "Discard Test Item":
				found_pickup = true
		_check(found_pickup, "manually discarding an item spawns a GroundItemPickup in the world")

		overworld._toggle_inventory()
		_check(not overworld._inventory_panel.visible, "toggle again closes the panel")
		_check(not overworld._pc.movement_paused_for_test(), "toggle again resumes PC movement")

		# 'C' keybinding (2026-07-12): opens the same panel directly to the Stats tab.
		var stats_event := InputEventAction.new()
		stats_event.action = &"toggle_stats"
		stats_event.pressed = true
		overworld._unhandled_input(stats_event)
		_check(overworld._inventory_panel.visible, "toggle_stats opens the panel")
		_check(overworld._inventory_panel.active_tab_for_test() == &"stats", "toggle_stats opens directly to the Stats tab")
		_check(overworld._pc.movement_paused_for_test(), "toggle_stats pauses PC movement")
		overworld._unhandled_input(stats_event)
		_check(not overworld._inventory_panel.visible, "toggle_stats again closes the panel")
		_check(not overworld._pc.movement_paused_for_test(), "toggle_stats again resumes PC movement")
	if _frames >= 5:
		print("ok overworld_demo inventory wiring smoke test complete")
		_instance.free()
		return true
	return false
