extends SceneTree

# Headless: the Chancer casino line set is >=20 distinct width-4 left-to-right paths (one cell per
# column, valid rows). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_casino_lines.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var lines: Array = PaylineLibrary.casino_lines(4)
	_check(lines.size() >= 20, ">=20 casino lines (got %d)" % lines.size())

	var seen: Dictionary = {}
	var all_ok: bool = true
	for line in lines:
		_check(line.size() == 4, "line has one cell per column (got %d)" % line.size())
		var key: String = ""
		for c: int in range(line.size()):
			var cell: Vector2i = line[c]
			if cell.x != c: all_ok = false          # ordered left-to-right, col == index
			if cell.y < 0 or cell.y > 2: all_ok = false  # valid row
			key += "%d," % cell.y
		seen[key] = true
	_check(all_ok, "every cell is in column order with a valid row 0..2")
	_check(seen.size() == lines.size(), "all lines are distinct paths (got %d unique of %d)" % [seen.size(), lines.size()])

	# Dispatch: casino profile -> casino_lines; default -> lines_for.
	_check(PaylineLibrary.lines_for_profile(&"casino", 4).size() == lines.size(), "profile casino -> casino_lines")
	_check(PaylineLibrary.lines_for_profile(&"default", 4).size() == PaylineLibrary.lines_for(4).size(), "profile default -> lines_for")

	print(("CASINO LINES TEST PASSED" if _failures == 0 else "CASINO LINES TEST FAILED: %d" % _failures))
	quit(_failures)
