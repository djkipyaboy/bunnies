extends SceneTree

# Headless test: TeamUpPaylineResolver, the symbol-matching sibling of PaylineResolver (which
# matches on ReelFace.result_tier — this matches on ReelFace.team_up_symbol instead). Pure grid
# logic, no scene needed. 2026-07-29 spec §4.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_payline_resolver.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _face(symbol: StringName) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.team_up_symbol = symbol
	return f

func _initialize() -> void:
	# A 2-column x 3-row grid: column 0 is all "surge" (a full column match); column 1 is mixed.
	var grid: Array = [
		[_face(&"surge"), _face(&"surge"), _face(&"surge")],
		[_face(&"surge"), _face(&"strike"), _face(&"strike")],
	]
	var lines: Array = PaylineLibrary.lines_for(2)
	_check(lines.size() == 5, "PaylineLibrary.lines_for(2) returns 5 lines (2 columns + 3 rows, no diagonals at width<3) (got %d)" % lines.size())

	var surge_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"surge")
	# Column 0 (all surge) scores. Row 0 ([0,0]=surge,[1,0]=surge) scores. Rows 1/2 mix surge/strike -> no.
	_check(surge_hits.size() == 2, "exactly 2 lines are all-surge (column 0 + row 0) (got %d)" % surge_hits.size())
	for hit: TeamUpPaylineResolver.SymbolHit in surge_hits:
		_check(hit.symbol == &"surge", "each hit records the queried symbol")
		_check(hit.length == hit.cells.size(), "length matches the cells array size")

	var strike_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"strike")
	_check(strike_hits.is_empty(), "no line is entirely 'strike' in this grid (got %d)" % strike_hits.size())

	var mend_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"mend")
	_check(mend_hits.is_empty(), "a symbol present nowhere in the grid scores no lines")

	print(("TEAM UP PAYLINE RESOLVER TEST PASSED" if _failures == 0 else "TEAM UP PAYLINE RESOLVER TEST FAILED: %d" % _failures))
	quit(_failures)
