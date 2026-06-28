extends SceneTree

# Headless test: EnemyLibrary variation (spec 2026-06-28 §2) — ferret = Flurry, stoat = Hunter's Mark,
# both with a stamina pool that affords the ability and NO Ultimate; rat = plain (no ability/pool).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_variation.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var ferret: Combatant = EnemyLibrary.make(&"ferret")
	_check(ferret.ability_id == &"flurry", "ferret ability = flurry")
	_check(ferret.resource_pool != null, "ferret has a resource pool")
	_check(ferret.resource_pool != null and ferret.resource_pool.can_afford({&"stamina": ferret.ability_cost}),
		"ferret pool affords Flurry")
	_check(ferret.ultimate_id == &"", "ferret has NO Ultimate")

	var stoat: Combatant = EnemyLibrary.make(&"stoat")
	_check(stoat.ability_id == &"hunters_mark", "stoat ability = hunters_mark")
	_check(stoat.resource_pool != null and stoat.resource_pool.can_afford({&"stamina": stoat.ability_cost}),
		"stoat pool affords Hunter's Mark")
	_check(stoat.ability_resource == &"stamina", "stoat ability spends stamina")
	_check(stoat.ultimate_id == &"", "stoat has NO Ultimate")

	var rat: Combatant = EnemyLibrary.make(&"rat")
	_check(rat.ability_id == &"", "rat has no ability")
	_check(rat.resource_pool == null, "rat has no resource pool")
	_check(rat.ultimate_id == &"", "rat has NO Ultimate")

	print(("ENEMY VARIATION TEST PASSED" if _failures == 0 else "ENEMY VARIATION TEST FAILED: %d" % _failures))
	quit(_failures)
