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
	var succ_before: int = _count(w.reels[0], ReelFace.ResultTier.SUCCESS)

	c.begin_turn()
	var ok: bool = c.apply_heft(2)   # default 2 conversions per reel
	_check(ok, "apply_heft succeeded with 3 stamina")
	_check(c.resource_pool.stamina == 1, "spent 2 stamina -> 1 left (got %d)" % c.resource_pool.stamina)
	_check(_count(c.turn_reels[0], ReelFace.ResultTier.FAILURE) == fail_before - 2, "turn reel 0: TWO fewer FAILUREs (got %d, want %d)" % [_count(c.turn_reels[0], ReelFace.ResultTier.FAILURE), fail_before - 2])
	_check(_count(c.turn_reels[0], ReelFace.ResultTier.SUCCESS) == succ_before + 2, "turn reel 0: TWO more SUCCESS")
	_check(_count(c.turn_reels[1], ReelFace.ResultTier.SUCCESS) == succ_before + 2, "turn reel 1 also hefted (+2)")
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
