extends SceneTree

# Headless: left-aligned payline scoring — longest run of one scoring tier from reel 1; pays if >=min_run;
# trailing mismatch caps the run; failure-tier start never scores. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_casino.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _face(tier: ReelFace.ResultTier) -> ReelFace:
	var f: ReelFace = ReelFace.new(); f.result_tier = tier; return f

# Build a 4-col grid; each column is [top, center, bottom]. We only populate the center row (row 1).
func _grid_center(tiers: Array) -> Array:
	var g: Array = []
	for t in tiers:
		g.append([_face(ReelFace.ResultTier.FAILURE), _face(t), _face(ReelFace.ResultTier.FAILURE)])
	return g

func _mid_line() -> Array:
	return [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]

func _initialize() -> void:
	var CS := ReelFace.ResultTier.CRIT_SUCCESS
	var S := ReelFace.ResultTier.SUCCESS
	var CF := ReelFace.ResultTier.CRIT_FAILURE

	# Run of 3 crit+ then a hit -> scores length 3, tier crit-success, cells = first 3.
	var hits: Array = PaylineResolver.evaluate_left_align(_grid_center([CS, CS, CS, S]), [_mid_line()], 3)
	_check(hits.size() == 1, "3-run scores one hit (got %d)" % hits.size())
	_check(hits[0].length == 3, "run length 3 (got %d)" % hits[0].length)
	_check(hits[0].tier == CS, "tier carried = crit-success")
	_check(hits[0].cells.size() == 3, "hit cells = matched prefix of 3 (got %d)" % hits[0].cells.size())

	# Run of only 2 from the left (crit, crit, hit, crit) -> below min_run -> no score.
	var hits2: Array = PaylineResolver.evaluate_left_align(_grid_center([CS, CS, S, CS]), [_mid_line()], 3)
	_check(hits2.is_empty(), "2-run does not score (got %d)" % hits2.size())

	# Full 4-run.
	var hits3: Array = PaylineResolver.evaluate_left_align(_grid_center([S, S, S, S]), [_mid_line()], 3)
	_check(hits3.size() == 1 and hits3[0].length == 4, "4-run scores length 4")

	# Failure tier at reel 1 -> never scores.
	var hits4: Array = PaylineResolver.evaluate_left_align(_grid_center([CF, CF, CF, CF]), [_mid_line()], 3)
	_check(hits4.is_empty(), "failure-tier start never scores")

	print(("PAYLINE CASINO TEST PASSED" if _failures == 0 else "PAYLINE CASINO TEST FAILED: %d" % _failures))
	quit(_failures)
