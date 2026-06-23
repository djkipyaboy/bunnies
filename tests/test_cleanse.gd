extends SceneTree

# Headless test: cleanse strips debuffs, keeps buffs, and restores derived initiative. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_cleanse.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.base_initiative = 50
	c.recompute_initiative()
	c.attach_effect(EffectLibrary.make(&"slow"))           # debuff: -20 initiative
	c.attach_effect(EffectLibrary.make(&"inspirational"))  # buff: +5 initiative
	_check(c.active_effects.size() == 2, "two effects attached (got %d)" % c.active_effects.size())
	_check(c.current_initiative == 35, "50 -20 +5 = 35 (got %d)" % c.current_initiative)

	var removed: int = c.cleanse()
	_check(removed == 1, "cleansed 1 debuff (got %d)" % removed)
	_check(c.active_effects.size() == 1, "buff remains (got %d effects)" % c.active_effects.size())
	_check(c.active_effects[0].id == &"inspirational", "the survivor is the buff")
	_check(c.current_initiative == 55, "50 +5 = 55 after debuff removed (got %d)" % c.current_initiative)

	print(("CLEANSE TEST PASSED" if _failures == 0 else "CLEANSE TEST FAILED: %d" % _failures))
	quit(_failures)
