extends SceneTree

## Headless smoke test: the TalentMenuPanel UI (Task 22) is wired into town_demo (Task 23, spec
## 2026-07-24-ability-talent-track-redesign-design.md §2/§6) — the N-key toggle opens/closes
## TalentMenuPanel, pauses/resumes PC movement while it's open, and guards against stacking with
## the InventoryMenuPanel (and vice versa) in both directions.

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
		_check(town._talent_panel != null, "TalentMenuPanel is built")
		_check(not town._talent_panel.visible, "TalentMenuPanel starts hidden")
		town._toggle_talents()
		_check(town._talent_panel.visible, "toggle opens the panel")
		_check(town._pc.movement_paused_for_test(), "toggle pauses PC movement")
		town._toggle_talents()
		_check(not town._talent_panel.visible, "toggle again closes the panel")
		_check(not town._pc.movement_paused_for_test(), "toggle again resumes PC movement")

		# N-keybinding.
		var talents_event := InputEventAction.new()
		talents_event.action = &"toggle_talents"
		talents_event.pressed = true
		town._unhandled_input(talents_event)
		_check(town._talent_panel.visible, "toggle_talents action opens the panel")
		_check(town._pc.movement_paused_for_test(), "toggle_talents action pauses PC movement")

		# Modal-stacking guard: interact must not fire while the talent panel is open.
		var villager: Villager = town._exterior.get_node("Villager0")
		var zone: Interactable = villager.get_node("InteractionZone")
		town._pc._tracked.append(zone)
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		town._unhandled_input(interact_event)
		_check(not town._dialogue_box.is_open(), "interact is blocked while the talent panel is open")

		town._unhandled_input(talents_event)
		_check(not town._talent_panel.visible, "toggle_talents action again closes the panel")

		# Guard both directions: opening one panel while the other is open is a no-op.
		town._toggle_inventory()
		_check(town._inventory_panel.visible, "sanity: inventory opens on its own")
		town._toggle_talents()
		_check(not town._talent_panel.visible, "opening Talents while Inventory is open is blocked")
		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "inventory closes")

		town._toggle_talents()
		_check(town._talent_panel.visible, "sanity: talents opens on its own")
		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "opening Inventory while Talents is open is blocked")
		town._toggle_stats()
		_check(not town._inventory_panel.visible, "opening Stats while Talents is open is blocked")
		town._toggle_talents()
		_check(not town._talent_panel.visible, "talents closes")
	if _frames >= 3:
		print("ok town_demo talents wiring smoke test complete")
		_instance.free()
		return true
	return false
