extends SceneTree

# Headless test: apply_heft converts one FAILURE->SUCCESS per turn-reel, spends Stamina, and does
# NOT mutate the underlying weapon reels (deep-copy guard).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_heft.gd

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
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 15.0
	w.reels.append(ActionReel.make_default(crushing))
	w.reels.append(ActionReel.make_default(crushing))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.stamina = 3; c.resource_pool.max_stamina = 5

	var fail_before: int = _count(w.reels[0], ReelFace.ResultTier.FAILURE)
	var critfail_before: int = _count(w.reels[0], ReelFace.ResultTier.CRIT_FAILURE)
	var succ_before: int = _count(w.reels[0], ReelFace.ResultTier.SUCCESS)
	# DEFAULT_COMPOSITION (5x scale, 2026-08-13 accuracy-stat spec §2): a default reel now carries
	# 10 FAILURE + 5 CRIT_FAILURE + 20 SUCCESS faces, not the old 2/1/4. apply_heft(2) here means
	# cost=2, conversions stays at its default of 3 (apply_heft(cost, conversions=3) — the
	# `conversions` value itself is a gameplay-balance number and is intentionally left untouched).
	# _heft_turn_reels converts FAILURE faces first, then CRIT_FAILURE only once FAILURE runs out —
	# with 10 FAILURE faces available, all 3 conversions land on FAILURE and CRIT_FAILURE is
	# untouched. This is a real, proportionally-weaker-than-before-scaling side effect of Heft
	# converting a FIXED count (3) instead of "all" misses (which it incidentally did at the old
	# 2 FAILURE + 1 CRIT_FAILURE scale) — flagged for playtest, not a decided design change.
	var conversions: int = 3

	c.begin_turn()
	var ok: bool = c.apply_heft(2)
	_check(ok, "apply_heft succeeded with 3 stamina")
	_check(c.resource_pool.stamina == 1, "spent 2 stamina -> 1 left (got %d)" % c.resource_pool.stamina)
	_check(_count(c.turn_reels[0], ReelFace.ResultTier.FAILURE) == fail_before - conversions, "turn reel 0: %d of %d FAILUREs converted (%d left, got %d)" % [conversions, fail_before, fail_before - conversions, _count(c.turn_reels[0], ReelFace.ResultTier.FAILURE)])
	_check(_count(c.turn_reels[0], ReelFace.ResultTier.CRIT_FAILURE) == critfail_before, "turn reel 0: CRIT_FAILURE untouched — the 3 conversions were fully absorbed by FAILURE's larger pool (got %d, want %d)" % [_count(c.turn_reels[0], ReelFace.ResultTier.CRIT_FAILURE), critfail_before])
	_check(_count(c.turn_reels[0], ReelFace.ResultTier.SUCCESS) == succ_before + conversions, "turn reel 0: +%d SUCCESS (got %d)" % [conversions, _count(c.turn_reels[0], ReelFace.ResultTier.SUCCESS)])
	_check(_count(c.turn_reels[1], ReelFace.ResultTier.SUCCESS) == succ_before + conversions, "turn reel 1 also hefted for the same %d conversions" % conversions)
	# Weapon untouched (deep-copy guard).
	_check(_count(w.reels[0], ReelFace.ResultTier.FAILURE) == fail_before, "WEAPON reel 0 FAILURE unchanged (got %d, want %d)" % [_count(w.reels[0], ReelFace.ResultTier.FAILURE), fail_before])

	# Unaffordable -> no change.
	var d: Combatant = Combatant.new()
	d.weapon = w
	d.resource_pool = ResourcePool.new(); d.resource_pool.stamina = 1
	d.begin_turn()
	_check(d.apply_heft(2) == false, "apply_heft fails with 1 stamina")
	_check(d.resource_pool.stamina == 1, "no stamina spent on failed heft")

	print(("HEFT TEST PASSED" if _failures == 0 else "HEFT TEST FAILED: %d" % _failures))
	quit(_failures)
