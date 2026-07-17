extends SceneTree

# Headless test: ActionReel.make_item_use — the combat item-use reel (2026-07-16 combat item-use
# targeting design §2/§3.1). 9 SUCCESS + 1 CRIT_SUCCESS faces, zero damage, NO failure tiers at all
# (a potion should never simply fail), excluded from paylines, does not charge the Bonus Meter.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd

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
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	var reel: ActionReel = ActionReel.make_item_use(mystic)
	_check(reel.faces.size() == 10, "10 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 9, "9 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 1, "1 crit-success face (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.FAILURE) == 0, "no failure faces — a potion never simply fails")
	_check(_count(reel, ReelFace.ResultTier.NEUTRAL) == 0, "no neutral faces")
	_check(_count(reel, ReelFace.ResultTier.CRIT_FAILURE) == 0, "no crit-failure faces")
	_check(not reel.is_weapon_attack, "is_weapon_attack = false (out of paylines)")
	_check(not reel.charges_meter, "item reel does NOT charge the Bonus Meter (the heal is the payoff)")
	_check(reel.damage_type == mystic, "carries the requested type")
	var all_zero: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.multiplier == 0.0)
	_check(all_zero, "every face deals zero direct damage")
	var no_rider: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.rider_effect_id == &"")
	_check(no_rider, "no rider on any face (heal applied by the orchestrator from the landed tier)")

	# Resolver propagates charges_meter onto the AttackResult and zeroes meter_gain, same as Rallying Cry.
	var resolver: CombatResolver = CombatResolver.new()
	var attacks: Array[CombatResolver.AttackResult] = resolver.resolve_combat_phase([reel], 9.0, mystic)
	_check(not attacks[0].charges_meter, "resolved item-use attack has charges_meter = false")
	_check(attacks[0].meter_gain == 0, "resolved item-use attack contributes 0 meter (got %d)" % attacks[0].meter_gain)

	# make_item_use() with no type argument still builds a valid reel (default null damage_type).
	var untyped: ActionReel = ActionReel.make_item_use()
	_check(untyped.damage_type == null, "damage_type defaults to null when not passed")
	_check(untyped.faces.size() == 10, "untyped reel still has 10 faces")

	print(("ITEM USE REEL TEST PASSED" if _failures == 0 else "ITEM USE REEL TEST FAILED: %d" % _failures))
	quit(_failures)
