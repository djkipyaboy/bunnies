extends SceneTree

# Headless test: Combatant.equip_weapon()/unequip_weapon() must re-apply apply_luck()/
# apply_finesse_accuracy() to the newly-equipped Weapon resource, since neither hook runs
# automatically as part of apply_stats() (they're non-idempotent, so they can't be — see
# combat/combatant.gd apply_luck()/apply_finesse_accuracy() doc comments). Prior to this fix,
# equip_weapon() called only apply_stats(), silently discarding a combatant's accumulated
# Luck/Finesse reel conversions on every weapon swap.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_equip_weapon_luck_finesse.gd

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

	# Luck 7 -> floor(7/3) = 2 crit-fail faces converted on a NEW weapon equipped mid-game.
	var c1: Combatant = Combatant.new()
	var s1: Stats = Stats.new(); s1.luck = 7
	c1.base_stats = s1
	var w1a: Weapon = Weapon.new(); w1a.reels.append(ActionReel.make_default(slashing))
	var base_cf: int = _count(w1a, T.CRIT_FAILURE)   # baseline BEFORE this weapon is ever equipped/converted
	c1.equip_weapon(w1a)
	var w1b: Weapon = Weapon.new(); w1b.reels.append(ActionReel.make_default(slashing))
	c1.equip_weapon(w1b)
	_check(_count(w1b, T.CRIT_FAILURE) == base_cf - 2, "equip_weapon() re-applies Luck 7 -> 2 fewer crit-fail faces on new weapon")
	_check(_count(w1b, T.CRIT_SUCCESS) == 7, "equip_weapon() re-applies Luck 7 -> baseline 5 + 2 converted crit-success faces on new weapon")

	# Finesse 7 -> floor(7/3) = 2 fail faces converted (mirrors Luck's threshold shape/pace).
	var c2: Combatant = Combatant.new()
	var s2: Stats = Stats.new(); s2.finesse = 7
	c2.base_stats = s2
	var w2: Weapon = Weapon.new(); w2.reels.append(ActionReel.make_default(slashing))
	var base_fail: int = _count(w2, T.FAILURE)
	c2.equip_weapon(w2)
	_check(_count(w2, T.FAILURE) == base_fail - 2, "equip_weapon() re-applies Finesse 7 -> 2 fewer fail faces (got %d, base %d)" % [_count(w2, T.FAILURE), base_fail])
	_check(_count(w2, T.SUCCESS) >= 2, "equip_weapon() re-applies Finesse 7 -> at least 2 more success faces")

	# unequip_weapon() falls back to a fresh Weapon.make_unarmed() — must also get conversions.
	var c3: Combatant = Combatant.new()
	var s3: Stats = Stats.new(); s3.luck = 15
	c3.base_stats = s3
	var w3: Weapon = Weapon.new(); w3.reels.append(ActionReel.make_default(slashing))
	c3.equip_weapon(w3)
	c3.unequip_weapon()
	_check(_count(c3.weapon, T.CRIT_FAILURE) == 0, "unequip_weapon() re-applies Luck 15 to unarmed fallback -> 0 crit-fail faces left")

	print(("EQUIP WEAPON LUCK/FINESSE TEST PASSED" if _failures == 0 else "EQUIP WEAPON LUCK/FINESSE TEST FAILED: %d" % _failures))
	quit(_failures)
