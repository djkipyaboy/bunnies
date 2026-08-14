extends SceneTree

# Headless test for ActionReel.make_default() face composition (DESIGN.md §4.4 success ladder).
# Scaled 5x (2026-08-13 accuracy-stat spec §2) so Luck/Finesse's per-point face conversions have
# real percentage granularity to work with. The reel is a physical 50-face strip — odds come from
# how many of each symbol sit on it, NOT hidden weights (protects "the reel IS the dice").
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_action_reel.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier:
			n += 1
	return n

func _initialize() -> void:
	var T := ReelFace.ResultTier
	var reel: ActionReel = ActionReel.make_default()

	_check(reel.faces.size() == 50, "default reel has 50 faces (got %d)" % reel.faces.size())

	_check(_count(reel, T.CRIT_FAILURE) == 5, "5 crit-failure symbols = 10%% (got %d)" % _count(reel, T.CRIT_FAILURE))
	_check(_count(reel, T.CRIT_SUCCESS) == 5, "5 crit-success symbols = 10%% (got %d)" % _count(reel, T.CRIT_SUCCESS))
	_check(_count(reel, T.SUCCESS) == 20, "20 success symbols = 40%% (got %d)" % _count(reel, T.SUCCESS))
	_check(_count(reel, T.FAILURE) == 10, "10 failure symbols = 20%% (got %d)" % _count(reel, T.FAILURE))
	_check(_count(reel, T.NEUTRAL) == 10, "10 neutral/utility symbols = 20%% (got %d)" % _count(reel, T.NEUTRAL))

	# Faces must be distinct objects so the resolver's chosen face maps to a unique strip index.
	var seen: Dictionary = {}
	for f: ReelFace in reel.faces:
		seen[f] = true
	_check(seen.size() == 50, "all 50 faces are distinct objects (got %d)" % seen.size())

	# Damaging tiers keep their multipliers; non-damaging tiers deal none.
	for f: ReelFace in reel.faces:
		match f.result_tier:
			T.SUCCESS:
				_check(is_equal_approx(f.multiplier, 1.0), "success multiplier 1.0")
			T.CRIT_SUCCESS:
				_check(is_equal_approx(f.multiplier, 2.0), "crit-success multiplier 2.0")

	print(("ACTION REEL TEST PASSED" if _failures == 0 else "ACTION REEL TEST FAILED: %d" % _failures))
	quit(_failures)
