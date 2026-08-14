extends SceneTree

# Headless test: Finesse's new accuracy hook (2026-08-13 accuracy-stat spec §2) — converts existing
# FAILURE faces to SUCCESS in place, same replace-mechanic shape and 3-points-per-face pace as
# Luck's crit-fail->crit-success hook, but on the disjoint fail/success face pool. Capped at
# however many fail faces exist on the reel (10 at the default 50-face reel's baseline -> caps at
# Finesse 30). Finesse's existing initiative role (turn_manager.gd) is untouched by this.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_finesse_accuracy_threshold.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(w: Weapon, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in w.reels[0].faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var T := ReelFace.ResultTier
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# Below threshold (Finesse 2, needs 3): no conversion.
	var w1: Weapon = Weapon.new(); w1.reels.append(ActionReel.make_default(slashing))
	var base_f: int = _count(w1, T.FAILURE)
	var base_s: int = _count(w1, T.SUCCESS)
	var c1: Combatant = Combatant.new(); c1.weapon = w1
	var s1: Stats = Stats.new(); s1.finesse = 2
	c1.base_stats = s1
	c1.apply_finesse_accuracy()
	_check(_count(w1, T.FAILURE) == base_f, "Finesse 2 (below threshold 3) converts 0 fail faces")
	_check(_count(w1, T.SUCCESS) == base_s, "Finesse 2 -> success count unchanged")
	_check(w1.reels[0].faces.size() == 50, "Finesse 2 -> total face count unchanged (replace, not additive)")

	# At Finesse 7 -> floor(7/3) = 2 faces converted.
	var w2: Weapon = Weapon.new(); w2.reels.append(ActionReel.make_default(slashing))
	var base_f2: int = _count(w2, T.FAILURE)
	var base_s2: int = _count(w2, T.SUCCESS)
	var c2: Combatant = Combatant.new(); c2.weapon = w2
	var s2: Stats = Stats.new(); s2.finesse = 7
	c2.base_stats = s2
	c2.apply_finesse_accuracy()
	_check(_count(w2, T.FAILURE) == base_f2 - 2, "Finesse 7 -> 2 fewer fail faces (got %d, base %d)" % [_count(w2, T.FAILURE), base_f2])
	_check(_count(w2, T.SUCCESS) == base_s2 + 2, "Finesse 7 -> 2 more success faces (got %d, base %d)" % [_count(w2, T.SUCCESS), base_s2])

	# Cap: Finesse 30 converts all 10 baseline fail faces (floor(30/3) = 10).
	var w3: Weapon = Weapon.new(); w3.reels.append(ActionReel.make_default(slashing))
	var c3: Combatant = Combatant.new(); c3.weapon = w3
	var s3: Stats = Stats.new(); s3.finesse = 30
	c3.base_stats = s3
	c3.apply_finesse_accuracy()
	_check(_count(w3, T.FAILURE) == 0, "Finesse 30 -> all 10 fail faces converted (capped, got %d)" % _count(w3, T.FAILURE))
	_check(_count(w3, T.SUCCESS) == 30, "Finesse 30 -> success rises from 20 to 30 (got %d)" % _count(w3, T.SUCCESS))

	# Points beyond the cap are wasted (player's explicit call, spec §2).
	var w4: Weapon = Weapon.new(); w4.reels.append(ActionReel.make_default(slashing))
	var c4: Combatant = Combatant.new(); c4.weapon = w4
	var s4: Stats = Stats.new(); s4.finesse = 999
	c4.base_stats = s4
	c4.apply_finesse_accuracy()
	_check(_count(w4, T.FAILURE) == 0, "Finesse 999 -> still only 0 fail faces (no over-conversion)")
	_check(_count(w4, T.SUCCESS) == 30, "Finesse 999 -> still only 30 success faces (capped, not unbounded)")

	# Crit-fail and crit-success are NEVER touched by this hook (disjoint face pool from Luck's hook).
	_check(_count(w4, T.CRIT_FAILURE) == 5, "Finesse never touches crit-fail count (still 5)")
	_check(_count(w4, T.CRIT_SUCCESS) == 5, "Finesse never touches crit-success count (still 5)")

	# Converted faces carry a real 1.0x multiplier, same as any other success face.
	for f: ReelFace in w3.reels[0].faces:
		if f.result_tier == T.SUCCESS:
			_check(is_equal_approx(f.multiplier, 1.0), "converted success face has 1.0x multiplier")

	print(("FINESSE ACCURACY THRESHOLD TEST PASSED" if _failures == 0 else "FINESSE ACCURACY THRESHOLD TEST FAILED: %d" % _failures))
	quit(_failures)
