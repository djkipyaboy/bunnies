extends SceneTree

## Headless smoke test: the equipment/inventory/banking UI is wired into town_demo (spec
## 2026-07-10-equipment-inventory-banking-ui-design.md §4) — the I-key toggle opens/closes
## InventoryMenuPanel and pauses/resumes PC movement while it's open, and blocks `interact`
## from stacking a dialogue/door transition on top of the panel while it's open.

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

		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "toggle again closes the panel")
		_check(not town._pc.movement_paused_for_test(), "toggle again resumes PC movement")
	if _frames >= 5:
		print("ok town_demo inventory wiring smoke test complete")
		_instance.free()
		return true
	return false
