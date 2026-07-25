extends SceneTree

## Headless smoke test: the TalentMenuPanel UI (Task 22) is wired into the overworld demo the same
## way it's wired into town_demo (Task 23) — N-key toggle opens/closes TalentMenuPanel, pauses/
## resumes PC movement, and guards against stacking with InventoryMenuPanel in both directions.
## Unlike town, the overworld is NOT a safe zone: respec_available is passed false.

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
		_check(overworld._talent_panel != null, "TalentMenuPanel is built")
		_check(not overworld._talent_panel.visible, "TalentMenuPanel starts hidden")
		overworld._toggle_talents()
		_check(overworld._talent_panel.visible, "toggle opens the panel")
		_check(overworld._pc.movement_paused_for_test(), "toggle pauses PC movement")

		# interact must not fire while the talent panel is open.
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		overworld._unhandled_input(interact_event)   # should no-op; nothing to assert beyond "doesn't crash"

		overworld._toggle_talents()
		_check(not overworld._talent_panel.visible, "toggle again closes the panel")
		_check(not overworld._pc.movement_paused_for_test(), "toggle again resumes PC movement")

		# N-keybinding.
		var talents_event := InputEventAction.new()
		talents_event.action = &"toggle_talents"
		talents_event.pressed = true
		overworld._unhandled_input(talents_event)
		_check(overworld._talent_panel.visible, "toggle_talents action opens the panel")
		overworld._unhandled_input(talents_event)
		_check(not overworld._talent_panel.visible, "toggle_talents action again closes the panel")

		# Guard both directions.
		overworld._toggle_inventory()
		_check(overworld._inventory_panel.visible, "sanity: inventory opens on its own")
		overworld._toggle_talents()
		_check(not overworld._talent_panel.visible, "opening Talents while Inventory is open is blocked")
		overworld._toggle_inventory()
		_check(not overworld._inventory_panel.visible, "inventory closes")

		overworld._toggle_talents()
		_check(overworld._talent_panel.visible, "sanity: talents opens on its own")
		overworld._toggle_inventory()
		_check(not overworld._inventory_panel.visible, "opening Inventory while Talents is open is blocked")
		overworld._toggle_talents()
		_check(not overworld._talent_panel.visible, "talents closes")
	if _frames >= 3:
		print("ok overworld_demo talents wiring smoke test complete")
		_instance.free()
		return true
	return false
