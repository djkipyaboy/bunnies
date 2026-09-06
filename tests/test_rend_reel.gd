extends SceneTree

# Headless test: ActionReel.make_rend + resolver per-face rider / zero-multiplier damage gating.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rend_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _one_reel(tier: ReelFace.ResultTier, mult: float, rider: StringName) -> ActionReel:
	var r: ActionReel = ActionReel.new()
	var f: ReelFace = ReelFace.new(); f.result_tier = tier; f.multiplier = mult; f.rider_effect_id = rider
	r.faces.append(f)
	return r

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# make_rend: hit faces carry bleed + 0 multiplier; non-hit faces carry no rider.
	var rend: ActionReel = ActionReel.make_rend(slashing)
	var hit_faces: int = 0
	for f: ReelFace in rend.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces += 1
			_check(f.multiplier == 0.0, "rend hit face has 0 multiplier")
			_check(f.rider_effect_id == &"bleed", "rend hit face carries bleed rider")
		else:
			_check(f.rider_effect_id == &"", "rend non-hit face has no rider")
	_check(hit_faces == 35, "rend has 35 hit faces (30 success + 5 crit, ability-composition spread; got %d)" % hit_faces)

	var resolver: CombatResolver = CombatResolver.new()
	var SU := ReelFace.ResultTier.SUCCESS

	# A 0-multiplier success with bleed rider + Might 5: NO direct damage, reports bleed.
	var a: Array = resolver.resolve_combat_phase([_one_reel(SU, 0.0, &"bleed")], 10.0, slashing, [], 1, 5)
	_check(a[0].final_damage == 0, "rend hit (mult 0) deals 0 direct damage even with Might 5 (got %d)" % a[0].final_damage)
	_check(a[0].rider_effect_id == &"bleed", "rend hit reports bleed rider")

	# Regression: a normal success (mult 1) with Might 5 still deals damage and carries no rider.
	var b: Array = resolver.resolve_combat_phase([_one_reel(SU, 1.0, &"")], 10.0, slashing, [], 1, 5)
	_check(b[0].final_damage > 0, "normal success still deals damage (got %d)" % b[0].final_damage)
	_check(b[0].rider_effect_id == &"", "normal success has no per-face rider")

	# Rank 2 (2026-09-06 warrior-rank2-content spec §2.1): the 5 crit-fail faces convert to
	# success faces (still 0-multiplier, still bleed-riddled) — 70% -> 80% hit rate.
	var rend2: ActionReel = ActionReel.make_rend(slashing, true)
	var hit_faces2: int = 0
	var crit_fail_faces2: int = 0
	for f: ReelFace in rend2.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
			crit_fail_faces2 += 1
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces2 += 1
			_check(f.multiplier == 0.0, "rend rank 2 hit face has 0 multiplier")
			_check(f.rider_effect_id == &"bleed", "rend rank 2 hit face carries bleed rider")
	_check(crit_fail_faces2 == 0, "rend rank 2 has 0 crit-fail faces (converted to success)")
	_check(hit_faces2 == 40, "rend rank 2 has 40 hit faces (80%% hit rate, got %d)" % hit_faces2)

	print(("REND REEL TEST PASSED" if _failures == 0 else "REND REEL TEST FAILED: %d" % _failures))
	quit(_failures)
