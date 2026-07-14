extends SceneTree

## Headless smoke test: the equipment/inventory/banking UI is wired into town_demo (spec
## 2026-07-10-equipment-inventory-banking-ui-design.md §4) — the I-key toggle opens/closes
## InventoryMenuPanel and pauses/resumes PC movement while it's open, and blocks `interact`
## from stacking a dialogue/door transition on top of the panel while it's open.
##
## Also covers the PC-movement-pause fix for dialogue/board panels (the PC could walk around
## while a Villager dialogue box or the Adventuring Board panel was open, since only the
## inventory panel ever called PCController.set_movement_paused()) — dialogue and board open/
## close must now pause/resume PC movement the same way the inventory panel does.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		_check(town._inventory_panel != null, "InventoryMenuPanel is built")
		_check(not town._inventory_panel.visible, "InventoryMenuPanel starts hidden")
		town._toggle_inventory()
		_check(town._inventory_panel.visible, "toggle opens the panel")
		_check(town._pc.movement_paused_for_test(), "toggle pauses PC movement")

		# Modal-stacking guard: interact must not fire while the inventory panel is open, even
		# when a real Interactable (a Villager) is in the PC's reach. Force one into reach
		# deterministically (no dependence on physics-frame overlap timing) and drive the real
		# _unhandled_input() code path with a synthesized action event.
		var villager: Villager = town._exterior.get_node("Villager0")
		var zone: Interactable = villager.get_node("InteractionZone")
		town._pc._tracked.append(zone)
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		town._unhandled_input(interact_event)
		_check(not town._dialogue_box.is_open(), "interact is blocked while inventory panel is open")

		town._inventory_panel.switch_tab_for_test(&"bag")
		var junk: Gear = Gear.new()
		junk.display_name = "Discard Test Item"
		town._party_inventory.gear.append(junk)
		town._inventory_panel._rebuild()
		town._inventory_panel.select_grid_item_for_test(junk, false)
		town._inventory_panel.press_discard_for_test()
		town._inventory_panel.confirm_discard_for_test()
		var found_pickup: bool = false
		for child in town._pc.get_parent().get_children():
			if child is GroundItemPickup and (child.item as Gear).display_name == "Discard Test Item":
				found_pickup = true
		_check(found_pickup, "manually discarding an item spawns a GroundItemPickup in the world")

		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "toggle again closes the panel")
		_check(not town._pc.movement_paused_for_test(), "toggle again resumes PC movement")

		# 'C' keybinding (2026-07-12): opens the same panel directly to the Stats tab.
		var stats_event := InputEventAction.new()
		stats_event.action = &"toggle_stats"
		stats_event.pressed = true
		town._unhandled_input(stats_event)
		_check(town._inventory_panel.visible, "toggle_stats opens the panel")
		_check(town._inventory_panel.active_tab_for_test() == &"stats", "toggle_stats opens directly to the Stats tab")
		_check(town._pc.movement_paused_for_test(), "toggle_stats pauses PC movement")
		town._unhandled_input(stats_event)
		_check(not town._inventory_panel.visible, "toggle_stats again closes the panel")
		_check(not town._pc.movement_paused_for_test(), "toggle_stats again resumes PC movement")

		# Dialogue box must also pause/resume PC movement (previously only the talking
		# Villager's own wandering was paused — the PC itself could still walk around).
		town._on_dialogue_requested(villager.dialogue, villager)
		_check(town._pc.movement_paused_for_test(), "dialogue request pauses PC movement")
		town._dialogue_box.close()
		_check(not town._pc.movement_paused_for_test(), "dialogue close resumes PC movement")

		# Adventuring Board panel must also pause/resume PC movement.
		var board: AdventuringBoard = town._exterior.get_node("AdventuringBoard")
		town._on_board_opened(board.entries)
		_check(town._board_panel.is_open(), "board opened")
		_check(town._pc.movement_paused_for_test(), "board open pauses PC movement")
		var board_close_event := InputEventAction.new()
		board_close_event.action = &"interact"
		board_close_event.pressed = true
		town._unhandled_input(board_close_event)
		_check(not town._board_panel.is_open(), "board closed via interact")
		_check(not town._pc.movement_paused_for_test(), "board close resumes PC movement")
	if _frames >= 5:
		print("ok town_demo inventory wiring smoke test complete")
		_instance.free()
		return true
	return false
