extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	# NOTE: outer-local captures below are wrapped in a 1-element Array, per this project's
	# documented "lambda-capture-by-value" gotcha (CLAUDE.md / memory
	# godot-toggle-button-and-test-bypass-gotchas) -- a lambda connected to a signal captures a
	# plain outer local by value, so reassigning it inside the lambda never propagates back.

	var species: SpeciesStep = SpeciesStep.new()
	var got_species_id: Array = [&""]
	species.selected.connect(func(id: StringName) -> void: got_species_id[0] = id)
	_check(species.info_text_for_test().contains("Might:"), "before any pick, the species step already shows the full stat glossary")
	species.select_for_test(&"otter")
	_check(got_species_id[0] == &"otter", "selecting Otter emits selected(&\"otter\") through a real button press")
	_check(species.selected_id_for_test() == &"otter", "the step tracks the selection internally")
	var otter_info: String = species.info_text_for_test()
	_check(otter_info.contains("Otter") and otter_info.contains("+1 Vigor"), "Otter's info text names the species and its passive")
	_check(otter_info.contains(StatCatalog.description(&"vigor")), "Otter's info text calls out what Vigor (its boosted stat) actually does")
	_check(otter_info.contains("Might:") and otter_info.contains("Luck:"), "Otter's info text still includes the full six-stat glossary")

	var class_step: ClassStep = ClassStep.new()
	var got_class_id: Array = [&""]
	class_step.selected.connect(func(id: StringName) -> void: got_class_id[0] = id)
	class_step.select_for_test(&"chancer")
	_check(got_class_id[0] == &"chancer", "selecting Chancer emits selected(&\"chancer\") through a real button press")
	var chancer_info: String = class_step.info_text_for_test()
	_check(chancer_info.contains(AbilityCatalog.display_name(&"reroll")) and chancer_info.contains(AbilityCatalog.description(&"reroll")), "Chancer's info text shows its base ability's real name+description")
	_check(chancer_info.contains(UltimateCatalog.display_name(&"wildcard_gamble")), "Chancer's info text shows its Ultimate's real name")
	_check(chancer_info.contains(AbilityCatalog.display_name(&"loaded_dice")), "Chancer's info text lists its L5 extra ability")

	var background_step: BackgroundStep = BackgroundStep.new()
	var got_background_id: Array = [&""]
	background_step.selected.connect(func(id: StringName) -> void: got_background_id[0] = id)
	background_step.select_for_test(&"reformed_vermin")
	_check(got_background_id[0] == &"reformed_vermin", "selecting Reformed Vermin emits selected(&\"reformed_vermin\") through a real button press")

	var name_step: NameStep = NameStep.new()
	var got_name: Array = [""]
	name_step.name_changed.connect(func(new_name: String) -> void: got_name[0] = new_name)
	name_step.enter_name_for_test("Martin")
	_check(got_name[0] == "Martin", "typing a name emits name_changed through the real LineEdit path")
	_check(not name_step.error_visible_for_test(), "a valid name shows no error")
	name_step.enter_name_for_test("Martin3")
	_check(name_step.error_visible_for_test(), "an invalid name (digit) shows the inline error")
	name_step.enter_name_for_test("")
	_check(not name_step.error_visible_for_test(), "an empty (not-yet-typed) name shows no error, only a disabled Next")

	print(("CHARACTER CREATION STEPS TEST PASSED" if _failures == 0 else "CHARACTER CREATION STEPS TEST FAILED: %d" % _failures))
	quit(_failures)
