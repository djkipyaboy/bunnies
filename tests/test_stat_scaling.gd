extends SceneTree

# Headless test: StatScaling's diminishing-returns power-stat curve (design spec 2026-08-28 §2.3).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stat_scaling.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# stat 0 -> exactly neutral (1.0), so an un-invested class sees no change from today's baseline.
	_check(is_equal_approx(StatScaling.multiplier(0), 1.0), "stat 0 -> 1.0 (got %f)" % StatScaling.multiplier(0))

	# K = 4.0: stat 4 -> 1 + 4/(4+4) = 1.5.
	_check(is_equal_approx(StatScaling.multiplier(4), 1.5), "stat 4 -> 1.5 (got %f)" % StatScaling.multiplier(4))

	# stat 8 -> 1 + 8/(8+4) = 1.6667.
	_check(is_equal_approx(StatScaling.multiplier(8), 5.0 / 3.0), "stat 8 -> 1.6667 (got %f)" % StatScaling.multiplier(8))

	# Monotonic, decelerating: each successive +4 stat adds a SMALLER bonus than the last.
	var m0: float = StatScaling.multiplier(0)
	var m4: float = StatScaling.multiplier(4)
	var m8: float = StatScaling.multiplier(8)
	var m12: float = StatScaling.multiplier(12)
	_check(m4 > m0 and m8 > m4 and m12 > m8, "multiplier strictly increases with stat")
	_check((m4 - m0) > (m8 - m4) and (m8 - m4) > (m12 - m8), "each successive step's gain is smaller (diminishing returns)")

	# Never below 1.0, even for a defensively-clamped negative stat (shouldn't occur, but no crash/dip).
	_check(StatScaling.multiplier(-3) == 1.0, "negative stat clamps to 1.0, not undefined/negative")

	print(("STAT SCALING TEST PASSED" if _failures == 0 else "STAT SCALING TEST FAILED: %d" % _failures))
	quit(_failures)
