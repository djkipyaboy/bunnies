extends SceneTree

# Headless test: ActionReel.make_rallying_cry — the Warden's no-damage party-shield reel
# (spec 2026-06-29 §3). 2 crit + 8 success faces, zero damage, excluded from paylines.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry_reel.gd

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
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	var reel: ActionReel = ActionReel.make_rallying_cry(earth)
	_check(reel.faces.size() == 10, "10 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 2, "2 crit-success faces (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 8, "8 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.FAILURE) == 0, "no failure faces")
	_check(_count(reel, ReelFace.ResultTier.NEUTRAL) == 0, "no neutral faces")
	_check(_count(reel, ReelFace.ResultTier.CRIT_FAILURE) == 0, "no crit-failure faces")
	_check(not reel.is_weapon_attack, "is_weapon_attack = false (out of paylines)")
	_check(reel.damage_type == earth, "carries the requested type")
	var all_zero: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.multiplier == 0.0)
	_check(all_zero, "every face deals zero direct damage")
	var no_rider: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.rider_effect_id == &"")
	_check(no_rider, "no rider on any face (shield applied by orchestrator from tier)")
	_check(not reel.charges_meter, "rally reel does NOT charge the Bonus Meter (its value is the party shield)")

	# Resolver propagates charges_meter onto the AttackResult and zeroes meter_gain for the rally reel.
	var resolver: CombatResolver = CombatResolver.new()
	var rally_attacks: Array[CombatResolver.AttackResult] = resolver.resolve_combat_phase([reel], 9.0, earth)
	_check(not rally_attacks[0].charges_meter, "resolved rally attack has charges_meter = false")
	_check(rally_attacks[0].meter_gain == 0, "resolved rally attack contributes 0 meter (got %d)" % rally_attacks[0].meter_gain)

	# A normal weapon reel still charges the meter (regression: the flag defaults true).
	var normal: ActionReel = ActionReel.make_default(earth)
	_check(normal.charges_meter, "default weapon reel charges the meter (flag defaults true)")

	print(("RALLYING CRY REEL TEST PASSED" if _failures == 0 else "RALLYING CRY REEL TEST FAILED: %d" % _failures))
	quit(_failures)
