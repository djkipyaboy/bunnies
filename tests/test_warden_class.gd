extends SceneTree

# Headless test: the Warden class profile (spec 2026-06-29 §2). Earth Earthstave, 3 reels, mana-only
# 12/12, meter cap 15, Rallying Cry (mana) + Earthquake. Luck 0 (Chancer-exclusive).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_warden_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(&"warden" in ClassLibrary.IDS, "warden is registered in ClassLibrary.IDS")

	var cc: CharacterClass = ClassLibrary.make(&"warden")
	_check(cc != null, "ClassLibrary.make(&\"warden\") returns a class")
	_check(cc.reel_count == 3, "3 reels (got %d)" % cc.reel_count)
	_check(cc.weapon_base_damage == 9.0, "Earthstave base 9 (got %s)" % str(cc.weapon_base_damage))
	_check(cc.ability_id == &"rallying_cry" and cc.ability_resource == &"mana" and cc.ability_cost == 4, "Rallying Cry: 4 mana")
	_check(cc.ultimate_id == &"earthquake", "Ultimate is Earthquake")
	_check(cc.meter_cap == 15, "meter cap 15 (match Seer, got %d)" % cc.meter_cap)
	_check(cc.base_max_stamina == 0, "mana-only (no stamina)")
	_check(cc.base_stats.luck == 0, "Luck 0 (Chancer-exclusive)")

	# Built combatant: mana-only pool derives to 12 (base 8 + Focus 4), starts full, no stamina rail.
	var w: Combatant = cc.build_combatant(true)
	_check(w.resource_pool.max_mana == 12, "max_mana = 8 + Focus 4 = 12 (got %d)" % w.resource_pool.max_mana)
	_check(w.resource_pool.mana == 12, "starts at full mana (got %d)" % w.resource_pool.mana)
	_check(w.resource_pool.max_stamina == 0, "no stamina rail (got %d)" % w.resource_pool.max_stamina)
	_check(w.bonus_meter.cap == 15, "combatant meter cap 15")
	_check(w.weapon.reels.size() == 3, "weapon has 3 reels")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	_check(w.weapon_type() == earth, "weapon type is Earth")

	print(("WARDEN CLASS TEST PASSED" if _failures == 0 else "WARDEN CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
