extends SceneTree

# Headless test: Luck's crit-face hook is a REPLACE mechanic (2026-08-13 accuracy-stat spec §2) —
# converts existing CRIT_FAILURE faces to CRIT_SUCCESS in place, not additive. Threshold pace
# unchanged (1 face per 3 Luck points), capped at however many crit-fail faces exist on the reel
# (5 at the default 50-face reel's baseline -> caps at Luck 15). Separately, Luck also grants extra
# scored payline lines via the extra_lines hook (spec §5.4, unaffected by this rework).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_luck_threshold.gd

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

	# Below threshold (Luck 2, needs 3): no conversion.
	var w1: Weapon = Weapon.new(); w1.reels.append(ActionReel.make_default(slashing))
	var base_cf: int = _count(w1, T.CRIT_FAILURE)
	var base_cs: int = _count(w1, T.CRIT_SUCCESS)
	var c1: Combatant = Combatant.new(); c1.weapon = w1
	var s1: Stats = Stats.new(); s1.luck = 2
	c1.base_stats = s1
	c1.apply_luck()
	_check(_count(w1, T.CRIT_FAILURE) == base_cf, "Luck 2 (below threshold 3) converts 0 crit-fail faces")
	_check(_count(w1, T.CRIT_SUCCESS) == base_cs, "Luck 2 -> crit-success count unchanged")
	_check(w1.reels[0].faces.size() == 50, "Luck 2 -> total face count unchanged (replace, not additive)")

	# At Luck 7 -> floor(7/3) = 2 faces converted.
	var w2: Weapon = Weapon.new(); w2.reels.append(ActionReel.make_default(slashing))
	var base_cf2: int = _count(w2, T.CRIT_FAILURE)
	var base_cs2: int = _count(w2, T.CRIT_SUCCESS)
	var c2: Combatant = Combatant.new(); c2.weapon = w2
	var s2: Stats = Stats.new(); s2.luck = 7
	c2.base_stats = s2
	c2.apply_luck()
	_check(_count(w2, T.CRIT_FAILURE) == base_cf2 - 2, "Luck 7 -> 2 fewer crit-fail faces (got %d, base %d)" % [_count(w2, T.CRIT_FAILURE), base_cf2])
	_check(_count(w2, T.CRIT_SUCCESS) == base_cs2 + 2, "Luck 7 -> 2 more crit-success faces (got %d, base %d)" % [_count(w2, T.CRIT_SUCCESS), base_cs2])
	_check(w2.reels[0].faces.size() == 50, "Luck 7 -> total face count unchanged (replace, not additive)")

	# Cap: Luck 15 exactly converts all 5 baseline crit-fail faces (5/3 -> floor is 5, matching the
	# reel's actual crit-fail count of 5 at 3-per-face pace: floor(15/3) = 5).
	var w3: Weapon = Weapon.new(); w3.reels.append(ActionReel.make_default(slashing))
	var c3: Combatant = Combatant.new(); c3.weapon = w3
	var s3: Stats = Stats.new(); s3.luck = 15
	c3.base_stats = s3
	c3.apply_luck()
	_check(_count(w3, T.CRIT_FAILURE) == 0, "Luck 15 -> all 5 crit-fail faces converted (capped, got %d)" % _count(w3, T.CRIT_FAILURE))
	_check(_count(w3, T.CRIT_SUCCESS) == 10, "Luck 15 -> crit-success doubles from 5 to 10 (got %d)" % _count(w3, T.CRIT_SUCCESS))

	# Points beyond the cap are wasted, never negative/over-converted (player's explicit call, spec §2).
	var w4: Weapon = Weapon.new(); w4.reels.append(ActionReel.make_default(slashing))
	var c4: Combatant = Combatant.new(); c4.weapon = w4
	var s4: Stats = Stats.new(); s4.luck = 999
	c4.base_stats = s4
	c4.apply_luck()
	_check(_count(w4, T.CRIT_FAILURE) == 0, "Luck 999 -> still only 0 crit-fail faces (no over-conversion)")
	_check(_count(w4, T.CRIT_SUCCESS) == 10, "Luck 999 -> still only 10 crit-success faces (capped, not unbounded)")

	# Converted faces carry a real 2.0x multiplier, same as any other crit-success face.
	for f: ReelFace in w3.reels[0].faces:
		if f.result_tier == T.CRIT_SUCCESS:
			_check(is_equal_approx(f.multiplier, 2.0), "converted crit-success face has 2.0x multiplier")

	# Extra payline lines: Luck 4 -> floor(4/4) = 1 extra line; Luck 3 -> 0. Unaffected by this rework.
	var c5: Combatant = Combatant.new()
	var s5: Stats = Stats.new(); s5.luck = 4
	c5.base_stats = s5
	_check(c5.luck_extra_lines(3).size() == 1, "Luck 4 -> 1 extra payline line (got %d)" % c5.luck_extra_lines(3).size())

	var c6: Combatant = Combatant.new()
	var s6: Stats = Stats.new(); s6.luck = 3
	c6.base_stats = s6
	_check(c6.luck_extra_lines(3).size() == 0, "Luck 3 (below threshold 4) -> 0 extra lines")

	print(("LUCK THRESHOLD TEST PASSED" if _failures == 0 else "LUCK THRESHOLD TEST FAILED: %d" % _failures))
	quit(_failures)
