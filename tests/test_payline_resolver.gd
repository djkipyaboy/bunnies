extends SceneTree

# Headless unit test for PaylineResolver (DESIGN spec 2026-06-20).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_payline_resolver.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else:
		_failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _face(tier: ReelFace.ResultTier) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	return f

# Build a 3-row x W-col grid from a [col][row] tier matrix.
func _grid(cols: Array) -> Array:
	var g: Array = []
	for col: Array in cols:
		g.append([_face(col[0]), _face(col[1]), _face(col[2])])
	return g

func _tier_count(hits: Array, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for h in hits:
		if h.tier == tier: n += 1
	return n

func _initialize() -> void:
	var CF := ReelFace.ResultTier.CRIT_FAILURE
	var FA := ReelFace.ResultTier.FAILURE
	var NE := ReelFace.ResultTier.NEUTRAL
	var SU := ReelFace.ResultTier.SUCCESS
	var CS := ReelFace.ResultTier.CRIT_SUCCESS

	# 3x3 all-success grid: every line (8) scores SUCCESS.
	var all_su: Array = _grid([[SU,SU,SU],[SU,SU,SU],[SU,SU,SU]])
	var hits_su: Array = PaylineResolver.evaluate(all_su, PaylineLibrary.lines_for(3))
	_check(hits_su.size() == 8, "all-success 3x3 -> 8 line hits (got %d)" % hits_su.size())
	_check(_tier_count(hits_su, SU) == 8, "all hits are SUCCESS")

	# Center row all crit, everything else fail: exactly the center-row line hits CRIT_SUCCESS (len 3).
	var center_crit: Array = _grid([[FA,CS,FA],[FA,CS,FA],[FA,CS,FA]])
	var hits_cc: Array = PaylineResolver.evaluate(center_crit, PaylineLibrary.lines_for(3))
	_check(_tier_count(hits_cc, CS) == 1, "one CRIT line (center row) (got %d)" % _tier_count(hits_cc, CS))
	var crit_hit = null
	for h in hits_cc:
		if h.tier == CS: crit_hit = h
	_check(crit_hit != null and crit_hit.length == 3, "crit line length 3")
	_check(_tier_count(hits_cc, FA) == 0, "FAILURE never scores")

	# One off-tier cell breaks a line.
	var broken: Array = _grid([[SU,SU,SU],[SU,NE,SU],[SU,SU,SU]])  # center cell of reel 1 differs
	var hits_b: Array = PaylineResolver.evaluate(broken, PaylineLibrary.lines_for(3))
	# center row [1,1,1] passes through (1,1)=NE so it cannot be an all-SUCCESS hit:
	var center_is_success: bool = false
	for h in hits_b:
		if h.tier == SU and h.cells == [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)]: center_is_success = true
	_check(not center_is_success, "off-tier cell breaks the center success line")

	# 3x2: a full crit column (length 3) and a 2-wide crit row (length 2) both score.
	var g2: Array = _grid([[CS,CS,CS],[CS,FA,FA]])  # reel 0 column all crit; top row both crit
	var hits2: Array = PaylineResolver.evaluate(g2, PaylineLibrary.lines_for(2))
	var len3: bool = false
	var len2: bool = false
	for h in hits2:
		if h.tier == CS and h.length == 3: len3 = true
		if h.tier == CS and h.length == 2: len2 = true
	_check(len3, "3x2 crit column scores at length 3")
	_check(len2, "3x2 crit 2-wide row scores at length 2")

	print(("PAYLINE RESOLVER TEST PASSED" if _failures == 0 else "PAYLINE RESOLVER TEST FAILED: %d" % _failures))
	quit(_failures)
