extends SceneTree

# Headless test: Luck needs multiple points per crit face (threshold, not 1:1), and separately
# grants extra scored payline lines via the extra_lines hook (spec §5.4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_luck_threshold.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _crit_faces(w: Weapon) -> int:
	var n: int = 0
	for f: ReelFace in w.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: n += 1
	return n

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# Below threshold (Luck 2, needs 3): no crit face added.
	var w1: Weapon = Weapon.new(); w1.reels.append(ActionReel.make_default(slashing))
	var base_crit: int = _crit_faces(w1)
	var c1: Combatant = Combatant.new(); c1.weapon = w1
	var s1: Stats = Stats.new(); s1.luck = 2
	c1.base_stats = s1
	c1.apply_luck()
	_check(_crit_faces(w1) == base_crit, "Luck 2 (below threshold 3) adds 0 crit faces")

	# At the threshold (Luck 7 -> floor(7/3) = 2 faces).
	var w2: Weapon = Weapon.new(); w2.reels.append(ActionReel.make_default(slashing))
	var base_crit2: int = _crit_faces(w2)
	var c2: Combatant = Combatant.new(); c2.weapon = w2
	var s2: Stats = Stats.new(); s2.luck = 7
	c2.base_stats = s2
	c2.apply_luck()
	_check(_crit_faces(w2) == base_crit2 + 2, "Luck 7 -> floor(7/3) = 2 crit faces added (got %d, base %d)" % [_crit_faces(w2), base_crit2])

	# Extra payline lines: Luck 4 -> floor(4/4) = 1 extra line; Luck 3 -> 0.
	var c3: Combatant = Combatant.new()
	var s3: Stats = Stats.new(); s3.luck = 4
	c3.base_stats = s3
	_check(c3.luck_extra_lines(3).size() == 1, "Luck 4 -> 1 extra payline line (got %d)" % c3.luck_extra_lines(3).size())

	var c4: Combatant = Combatant.new()
	var s4: Stats = Stats.new(); s4.luck = 3
	c4.base_stats = s4
	_check(c4.luck_extra_lines(3).size() == 0, "Luck 3 (below threshold 4) -> 0 extra lines")

	print(("LUCK THRESHOLD TEST PASSED" if _failures == 0 else "LUCK THRESHOLD TEST FAILED: %d" % _failures))
	quit(_failures)
