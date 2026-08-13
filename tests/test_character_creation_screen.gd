extends SceneTree

## Scene-level test for CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## Drives it through all 4 steps via the actual panel signals/button presses -- never calling any
## private build/finalize method directly -- per the project's "a test that calls signal.emit()
## directly proves nothing about a real UI path" lesson (memory
## godot-toggle-button-and-test-bypass-gotchas).

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/character_creation_screen.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var screen: CharacterCreationScreen = _instance

		_check(screen.current_step_for_test() == &"species", "screen opens on the Species step")
		_check(not screen.can_advance_for_test(), "Next is disabled with nothing picked yet")

		screen.select_species_for_test(&"hare")
		_check(screen.can_advance_for_test(), "Next enables once Species is picked")
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"class", "Next advances to the Class step")
		_check(not screen.can_advance_for_test(), "Next is disabled again on the new step with nothing picked")

		screen.select_class_for_test(&"warrior")
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"background", "Next advances to the Background step")

		screen.select_background_for_test(&"reformed_vermin")
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"name", "Next advances to the Name step")

		# Back-and-forth navigation preserves earlier picks (spec, "Navigation & validation").
		screen.press_back_for_test()
		_check(screen.current_step_for_test() == &"background", "Back returns to the Background step")
		screen.press_back_for_test()
		_check(screen.current_step_for_test() == &"class", "Back returns to the Class step")
		_check(screen.can_advance_for_test(), "the earlier Class pick is still there after navigating back")
		screen.press_next_for_test()
		screen.press_next_for_test()
		_check(screen.current_step_for_test() == &"name", "forward navigation returns to the Name step with every earlier pick intact")

		_check(not screen.can_advance_for_test(), "Finalize is disabled with no name entered")
		screen.enter_name_for_test("Martin")
		_check(screen.can_advance_for_test(), "Finalize enables once a valid name is entered")
		_check(screen.reel_preview_text_for_test().find("Reformed Vermin") != -1, "the reel preview reflects the Background pick made 2 steps ago, not just the current step")

		# Lambda-capture-by-value gotcha (project memory godot-toggle-button-and-test-bypass-gotchas):
		# a lambda connected to a signal captures outer locals BY VALUE, so a bare `var created_pc`
		# reassigned inside the lambda would never propagate back to this scope. Wrap in a
		# 1-element Array and write/read through index 0 instead.
		var created_pc: Array = [null]
		screen.character_created.connect(func(pc: Combatant) -> void: created_pc[0] = pc)
		screen.press_next_for_test()

		_check(created_pc[0] != null, "pressing Finalize on the Name step emits character_created with a real Combatant")
		_check(created_pc[0].display_name == "Martin", "the finalized Combatant carries the entered name")
		_check(created_pc[0].heritage != null and created_pc[0].heritage.species_name == "Hare", "the finalized Combatant carries the chosen heritage")
		_check(created_pc[0].background != null and created_pc[0].background.background_name == "Reformed Vermin", "the finalized Combatant carries the chosen background")
		_check(created_pc[0].class_id == &"warrior", "the finalized Combatant carries the chosen (tentative) class")
		_check(not created_pc[0].class_is_locked, "the finalized Combatant's class starts unlocked, pending the future Class Trial & Lock-In mechanic")
		_check(created_pc[0].background.signature_face in created_pc[0].weapon.reels[0].faces, "the background's signature face is inserted into the PC's starting reel strip")

	if _frames >= 2:
		print("ok character-creation-screen scene test complete")
		_instance.free()
		return true
	return false
