extends SceneTree

# Headless unit test for PaylineLibrary line generation (DESIGN spec 2026-06-20).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_payline_library.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else:
		_failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _has_line(lines: Array, want: Array) -> bool:
	for line: Array in lines:
		if line == want:
			return true
	return false

func _initialize() -> void:
	_check(PaylineLibrary.lines_for(2).size() == 5, "3x2 -> 5 lines (got %d)" % PaylineLibrary.lines_for(2).size())
	_check(PaylineLibrary.lines_for(3).size() == 8, "3x3 -> 8 lines (got %d)" % PaylineLibrary.lines_for(3).size())
	_check(PaylineLibrary.lines_for(4).size() == 11, "3x4 -> 11 lines (got %d)" % PaylineLibrary.lines_for(4).size())
	_check(PaylineLibrary.lines_for(5).size() == 14, "3x5 -> 14 lines (got %d)" % PaylineLibrary.lines_for(5).size())

	var l3: Array = PaylineLibrary.lines_for(3)
	_check(_has_line(l3, [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)]), "3x3 has center row")
	_check(_has_line(l3, [Vector2i(0,0), Vector2i(0,1), Vector2i(0,2)]), "3x3 has reel-0 column")
	_check(_has_line(l3, [Vector2i(0,0), Vector2i(1,1), Vector2i(2,2)]), "3x3 has down-right diagonal")
	_check(_has_line(l3, [Vector2i(0,2), Vector2i(1,1), Vector2i(2,0)]), "3x3 has up-right diagonal")

	# Row length scales with width; columns/diagonals stay length 3.
	var l4: Array = PaylineLibrary.lines_for(4)
	_check(_has_line(l4, [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)]), "3x4 center row has length 4")
	# 3x2 has no diagonals (need 3 columns); rows are length 2.
	_check(_has_line(PaylineLibrary.lines_for(2), [Vector2i(0,0), Vector2i(1,0)]), "3x2 top row has length 2")

	print(("PAYLINE LIBRARY TEST PASSED" if _failures == 0 else "PAYLINE LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
