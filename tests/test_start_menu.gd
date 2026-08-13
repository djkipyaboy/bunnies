extends SceneTree

## Scene-level test for StartMenu (spec 2026-08-13-start-menu-design.md). Drives New Game and the
## full Species->Class->Background->Name->Finalize walkthrough via real signals/button presses (the
## same CharacterCreationScreen test hooks its own test file uses), then confirms CombatHandoff is
## populated and the scene actually transitions to town_demo.tscn. Does NOT press Quit -- that calls
## get_tree().quit(), which would terminate this test process; wiring is confirmed by inspection
## instead (see the final checks).

var _instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/start_menu.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var menu: StartMenu = _instance

		_check(menu.continue_disabled_for_test(), "Continue is permanently disabled (no save system exists)")

		menu.press_new_game_for_test()
		var screen: CharacterCreationScreen = menu.creation_screen_for_test()
		_check(screen != null, "pressing New Game instances a real CharacterCreationScreen")

		screen.select_species_for_test(&"hare")
		screen.press_next_for_test()
		screen.select_class_for_test(&"vanguard")
		screen.press_next_for_test()
		screen.select_background_for_test(&"abbey_cook")
		screen.press_next_for_test()
		screen.enter_name_for_test("Rose")
		screen.press_next_for_test()   # Finalize -> emits character_created

		var handoff: Node = root.get_node("CombatHandoff")
		_check(handoff.pc != null, "Finalize populates CombatHandoff.pc")
		_check(handoff.pc.display_name == "Rose", "CombatHandoff.pc carries the created PC's name")
		_check(handoff.pc.level == 4, "CombatHandoff.pc's level was forced to 4 by seed_demo_party()")
		_check(handoff.companions.size() == 1, "CombatHandoff.companions carries the seeded companion (Basil)")
		_check(handoff.bench.size() == 5, "CombatHandoff.bench carries the seeded bench (excludes Vanguard+Skirmisher)")
		_check(handoff.party_inventory != null, "CombatHandoff.party_inventory is populated")
		_check(handoff.vault != null, "CombatHandoff.vault is populated")

	if _frames >= 4:
		var current: Node = current_scene
		_check(current is TownDemo, "the scene actually transitioned to town_demo.tscn after Finalize")
		print("ok start-menu scene test complete")
		if current != null:
			current.free()
		if _instance != null:
			_instance.free()
		quit(_failures)
		return true
	return false
