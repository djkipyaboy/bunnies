extends SceneTree

# Headless test for InitiativeReel.digits_for_value() (2026-08-16 visible-initiative-reels spec §2).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_initiative_reel_digits.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(InitiativeReel.digits_for_value(100) == Vector2i(0, 0), "value 100 (raw 00) -> digits (0, 0)")
	_check(InitiativeReel.digits_for_value(1) == Vector2i(0, 1), "value 1 -> digits (0, 1)")
	_check(InitiativeReel.digits_for_value(47) == Vector2i(4, 7), "value 47 -> digits (4, 7)")
	_check(InitiativeReel.digits_for_value(99) == Vector2i(9, 9), "value 99 -> digits (9, 9)")
	_check(InitiativeReel.digits_for_value(10) == Vector2i(1, 0), "value 10 -> digits (1, 0)")
	_check(InitiativeReel.digits_for_value(50) == Vector2i(5, 0), "value 50 -> digits (5, 0)")

	print(("INITIATIVE REEL DIGITS TEST PASSED" if _failures == 0 else "INITIATIVE REEL DIGITS TEST FAILED: %d" % _failures))
	quit(_failures)
