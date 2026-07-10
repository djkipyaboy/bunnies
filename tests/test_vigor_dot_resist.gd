extends SceneTree

# Headless test: Vigor reduces incoming DoT tick damage (spec §5.2), with a floor so it's never
# full immunity, and never touches beneficial ticks (Regen/HoT).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_vigor_dot_resist.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var zero: Combatant = Combatant.new()
	_check(is_equal_approx(zero.dot_damage_multiplier(), 1.0), "0 Vigor -> 1.0 (no resist)")

	var some: Combatant = Combatant.new()
	var s: Stats = Stats.new(); s.vigor = 4
	some.base_stats = s
	_check(is_equal_approx(some.dot_damage_multiplier(), 0.8), "4 Vigor -> 1.0 - 4*0.05 = 0.8 (got %f)" % some.dot_damage_multiplier())

	var capped: Combatant = Combatant.new()
	var s2: Stats = Stats.new(); s2.vigor = 20   # would be 0.0 uncapped
	capped.base_stats = s2
	_check(is_equal_approx(capped.dot_damage_multiplier(), 0.4), "20 Vigor hits the 0.4 floor (got %f)" % capped.dot_damage_multiplier())

	print(("VIGOR DOT RESIST TEST PASSED" if _failures == 0 else "VIGOR DOT RESIST TEST FAILED: %d" % _failures))
	quit(_failures)
