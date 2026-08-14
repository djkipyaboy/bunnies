extends SceneTree

# Headless test: ActionReel.make_ability_attack() — the shared composition for every reel that
# exists because of a resource-costed ability (2026-08-13 accuracy-stat spec §2). Replaces the old
# RIDER_COMPOSITION/make_rider_attack(): removes the NEUTRAL tier entirely and lands hit rate at
# 70% (before any Finesse/Luck conversion), out of a 50-face strip: 5 crit-fail / 10 fail / 0
# neutral / 30 success / 5 crit-success.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ability_attack_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var T := ReelFace.ResultTier
	var reel: ActionReel = ActionReel.make_ability_attack(null, &"sundered")

	_check(reel.is_weapon_attack, "make_ability_attack reel joins paylines (unlike Rend)")
	_check(reel.faces.size() == 50, "50-face strip (got %d)" % reel.faces.size())
	_check(_count(reel, T.CRIT_FAILURE) == 5, "5 crit-failure faces (got %d)" % _count(reel, T.CRIT_FAILURE))
	_check(_count(reel, T.FAILURE) == 10, "10 failure faces (got %d)" % _count(reel, T.FAILURE))
	_check(_count(reel, T.NEUTRAL) == 0, "zero neutral faces — the whole point of this composition")
	_check(_count(reel, T.SUCCESS) == 30, "30 success faces (got %d)" % _count(reel, T.SUCCESS))
	_check(_count(reel, T.CRIT_SUCCESS) == 5, "5 crit-success faces (got %d)" % _count(reel, T.CRIT_SUCCESS))

	var hit_count: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == T.SUCCESS or f.result_tier == T.CRIT_SUCCESS:
			hit_count += 1
			_check(f.multiplier > 0.0, "hit face keeps real damage multiplier")
			_check(f.rider_effect_id == &"sundered", "hit face carries the requested rider")
	_check(hit_count == 35, "35 hit faces (30 success + 5 crit-success) = 70%% hit rate (got %d)" % hit_count)

	# No-rider variant: used by every plain reel-count-adding ability (Flurry, Rampage, etc.)
	var no_rider: ActionReel = ActionReel.make_ability_attack(null)
	var no_rider_hit: bool = no_rider.faces.all(func(f: ReelFace) -> bool:
		return f.rider_effect_id == &"" or (f.result_tier != T.SUCCESS and f.result_tier != T.CRIT_SUCCESS))
	_check(no_rider_hit, "no rider_id passed -> no face carries a rider")

	var cc_reel: ActionReel = ActionReel.make_ability_attack(null, &"weakened", true)
	_check(cc_reel.bonus_vs_cc, "bonus_vs_cc flag set when requested")
	var plain_reel: ActionReel = ActionReel.make_ability_attack(null, &"rooted")
	_check(not plain_reel.bonus_vs_cc, "bonus_vs_cc defaults false")

	print(("ABILITY ATTACK REEL TEST PASSED" if _failures == 0 else "ABILITY ATTACK REEL TEST FAILED: %d" % _failures))
	quit(_failures)
