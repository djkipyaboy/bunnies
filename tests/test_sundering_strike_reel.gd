extends SceneTree

# Headless test: ActionReel.make_sundering_strike — real-damage reel + sundered rider, with a
# rank-2 accuracy bump mirroring Rend's own (see tests/test_rend_reel.gd).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# Rank<2 (default): 70% hit rate, real damage on SUCCESS/CRIT_SUCCESS, sundered rider.
	var reel1: ActionReel = ActionReel.make_sundering_strike(slashing)
	var hit_faces1: int = 0
	var crit_fail_faces1: int = 0
	for f: ReelFace in reel1.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			crit_fail_faces1 += 1
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces1 += 1
			_check(f.multiplier > 0.0, "rank<2 hit face keeps real damage")
			_check(f.rider_effect_id == &"sundered", "rank<2 hit face carries sundered rider")
	_check(crit_fail_faces1 == 5, "rank<2 has 5 crit-fail faces (got %d)" % crit_fail_faces1)
	_check(hit_faces1 == 35, "rank<2 has 35 hit faces (70%% hit rate, got %d)" % hit_faces1)

	# Rank 2: crit-fail faces convert to success (real damage + sundered rider), 80% hit rate.
	var reel2: ActionReel = ActionReel.make_sundering_strike(slashing, true)
	var hit_faces2: int = 0
	var crit_fail_faces2: int = 0
	for f: ReelFace in reel2.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			crit_fail_faces2 += 1
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces2 += 1
			_check(f.multiplier > 0.0, "rank 2 hit face keeps real damage")
			_check(f.rider_effect_id == &"sundered", "rank 2 hit face carries sundered rider")
	_check(crit_fail_faces2 == 0, "rank 2 has 0 crit-fail faces (converted to success)")
	_check(hit_faces2 == 40, "rank 2 has 40 hit faces (80%% hit rate, got %d)" % hit_faces2)

	print(("SUNDERING STRIKE REEL TEST PASSED" if _failures == 0 else "SUNDERING STRIKE REEL TEST FAILED: %d" % _failures))
	quit(_failures)
