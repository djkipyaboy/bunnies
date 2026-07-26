extends SceneTree

## Headless smoke test: the TalentMenuPanel UI (Task 22) is wired into the dungeon demo the same
## way it's wired into town_demo/overworld_demo (Task 23) — N-key toggle opens/closes
## TalentMenuPanel, pauses/resumes PC movement, and guards against stacking with
## InventoryMenuPanel in both directions. Like the overworld, the dungeon is NOT a safe zone:
## respec_available is passed false.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var dungeon: DungeonDemo = _instance
		_check(dungeon._talent_panel != null, "TalentMenuPanel is built")
		_check(not dungeon._talent_panel.visible, "TalentMenuPanel starts hidden")
		dungeon._toggle_talents()
		_check(dungeon._talent_panel.visible, "toggle opens the panel")
		_check(dungeon._pc.movement_paused_for_test(), "toggle pauses PC movement")
		_check(dungeon._talent_panel.party_tab_count() == dungeon._companions.size() + 1, "talent panel shows one tab per active party member (PC + companions, got %d)" % dungeon._talent_panel.party_tab_count())
		_check(dungeon._talent_panel.viewed_combatant_for_test() == dungeon._pc_combatant, "the talent panel defaults to viewing the PC")
		if dungeon._companions.size() > 0:
			_check(dungeon._talent_panel.press_party_tab_for_test(1), "switching to the first companion's tab succeeds")
			_check(dungeon._talent_panel.viewed_combatant_for_test() == dungeon._companions[0], "the panel now views the real companion instance, not a copy")

		# interact must not fire while the talent panel is open.
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		dungeon._unhandled_input(interact_event)   # should no-op; nothing to assert beyond "doesn't crash"

		dungeon._toggle_talents()
		_check(not dungeon._talent_panel.visible, "toggle again closes the panel")
		_check(not dungeon._pc.movement_paused_for_test(), "toggle again resumes PC movement")

		# N-keybinding.
		var talents_event := InputEventAction.new()
		talents_event.action = &"toggle_talents"
		talents_event.pressed = true
		dungeon._unhandled_input(talents_event)
		_check(dungeon._talent_panel.visible, "toggle_talents action opens the panel")
		dungeon._unhandled_input(talents_event)
		_check(not dungeon._talent_panel.visible, "toggle_talents action again closes the panel")

		# Guard both directions.
		dungeon._toggle_inventory()
		_check(dungeon._inventory_panel.visible, "sanity: inventory opens on its own")
		dungeon._toggle_talents()
		_check(not dungeon._talent_panel.visible, "opening Talents while Inventory is open is blocked")
		dungeon._toggle_inventory()
		_check(not dungeon._inventory_panel.visible, "inventory closes")

		dungeon._toggle_talents()
		_check(dungeon._talent_panel.visible, "sanity: talents opens on its own")
		dungeon._toggle_inventory()
		_check(not dungeon._inventory_panel.visible, "opening Inventory while Talents is open is blocked")
		dungeon._toggle_talents()
		_check(not dungeon._talent_panel.visible, "talents closes")
	if _frames >= 3:
		print("ok dungeon_demo talents wiring smoke test complete")
		_instance.free()
		return true
	return false
