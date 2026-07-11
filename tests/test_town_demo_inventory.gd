extends SceneTree

## Headless smoke test: the equipment/inventory/banking UI is wired into town_demo (spec
## 2026-07-10-equipment-inventory-banking-ui-design.md §4) — the I-key toggle opens/closes
## InventoryMenuPanel and pauses/resumes PC movement while it's open.

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
		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "toggle again closes the panel")
		_check(not town._pc.movement_paused_for_test(), "toggle again resumes PC movement")
	if _frames >= 5:
		print("ok town_demo inventory wiring smoke test complete")
		_instance.free()
		return true
	return false
