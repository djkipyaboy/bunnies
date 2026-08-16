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
	var c: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	_check(c.heritage == null, "a Combatant built directly via ClassLibrary has no heritage by default")
	_check(c.background == null, "a Combatant built directly via ClassLibrary has no background by default")
	_check(c.class_is_locked == false, "class_is_locked defaults to false")

	c.heritage = HeritageLibrary.make(&"hare")
	c.background = BackgroundLibrary.make(&"abbey_cook")
	c.class_is_locked = true
	_check(c.heritage.species_name == "Hare", "heritage can be assigned and read back")
	_check(c.background.background_name == "Community Chef", "background can be assigned and read back")
	_check(c.class_is_locked, "class_is_locked can be assigned and read back")

	print(("COMBATANT CREATION FIELDS TEST PASSED" if _failures == 0 else "COMBATANT CREATION FIELDS TEST FAILED: %d" % _failures))
	quit(_failures)
