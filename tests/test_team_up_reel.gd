extends SceneTree

# Headless test: ReelFace.team_up_symbol (the third "nullable field" kind, alongside the existing
# Action-reel and Initiative-reel fields — see reel_face.gd's own doc-comment) and TeamUpReel's
# make_default() factory (2026-07-29 UTIL-reel jackpot spec §4). Pure data, no scene needed.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var f: ReelFace = ReelFace.new()
	_check(f.team_up_symbol == &"", "team_up_symbol defaults to empty (unused by Action/Initiative faces)")
	f.team_up_symbol = &"strike"
	_check(f.team_up_symbol == &"strike", "team_up_symbol is a settable StringName")
	_check(f.result_tier == ReelFace.ResultTier.SUCCESS, "setting team_up_symbol leaves the Action-reel default fields untouched")

	var reel: TeamUpReel = TeamUpReel.make_default([[&"strike", 3], [&"mend", 2], [&"ward", 2], [&"break", 2], [&"surge", 1]])
	_check(reel is Reel, "TeamUpReel is a real Reel subclass")
	_check(reel.faces.size() == 10, "make_default builds exactly one face per composition count (got %d)" % reel.faces.size())

	var counts: Dictionary = {}
	for face: ReelFace in reel.faces:
		counts[face.team_up_symbol] = counts.get(face.team_up_symbol, 0) + 1
	_check(counts.get(&"strike", 0) == 3, "3 strike faces (got %d)" % counts.get(&"strike", 0))
	_check(counts.get(&"mend", 0) == 2, "2 mend faces (got %d)" % counts.get(&"mend", 0))
	_check(counts.get(&"ward", 0) == 2, "2 ward faces (got %d)" % counts.get(&"ward", 0))
	_check(counts.get(&"break", 0) == 2, "2 break faces (got %d)" % counts.get(&"break", 0))
	_check(counts.get(&"surge", 0) == 1, "1 surge face (got %d)" % counts.get(&"surge", 0))

	var landed: ReelFace = reel.spin()
	_check(landed != null and landed.team_up_symbol != &"", "spin() (inherited from Reel, no override needed) returns a real tagged face")

	print(("TEAM UP REEL TEST PASSED" if _failures == 0 else "TEAM UP REEL TEST FAILED: %d" % _failures))
	quit(_failures)
