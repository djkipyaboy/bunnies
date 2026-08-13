extends SceneTree

## Regression for the "test both CombatHandoff paths" lesson (memory test-both-handoff-paths.md):
## the tutorial's auto-start (town_demo.gd, "accepted_quest_ids.is_empty()") was only ever verified
## through the OLD fresh-boot fallback path (tests/test_town_demo_tutorial_autostart.gd). This
## drives the REAL new-game path -- StartMenu -> CharacterCreationScreen -> seed_demo_party(pc) ->
## CombatHandoff -> town_demo.tscn -- and confirms the tutorial still auto-accepts on the far side,
## instead of just trusting that a fresh PartyInventory happens to behave the same way.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/start_menu.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var menu: StartMenu = _instance
		menu.press_new_game_for_test()
		var screen: CharacterCreationScreen = menu.creation_screen_for_test()
		screen.select_species_for_test(&"otter")
		screen.press_next_for_test()
		screen.select_class_for_test(&"seer")
		screen.press_next_for_test()
		screen.select_background_for_test(&"abbey_cook")
		screen.press_next_for_test()
		screen.enter_name_for_test("Fern")
		screen.press_next_for_test()   # Finalize -> character_created -> change_scene_to_file

	if _frames >= 4:
		var current: Node = current_scene
		_check(current is TownDemo, "the new-game path really did land in town_demo.tscn")
		if current is TownDemo:
			var town: TownDemo = current
			_check(town._party_inventory.has_accepted_quest(&"tutorial"), "the tutorial auto-accepts on the NEW start-menu path, not just the old fresh-boot fallback")
			_check(town._pc_combatant.display_name == "Fern", "the town's PC really is the one created via the start menu")
		print("ok start-menu tutorial-autostart regression complete")
		if _instance != null:
			_instance.free()
		if current != null:
			current.free()
		return true
	return false
