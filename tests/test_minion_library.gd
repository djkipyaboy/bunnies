extends SceneTree

# Headless test for MinionLibrary.make() (2026-08-16 minion-summoning-class spec §3). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var baseline: Combatant = MinionLibrary.make(false)
	_check(baseline.is_player, "baseline minion is_player = true (ally side)")
	_check(baseline.is_minion, "baseline minion is_minion = true")
	_check(baseline.acts_last, "baseline minion acts_last = true")
	_check(baseline.weapon == null, "baseline minion has no weapon (weaponless, like a target dummy)")
	_check(baseline.is_alive(), "baseline minion starts alive")
	_check(baseline.max_hp == 15, "baseline minion max_hp = 15 (got %d)" % baseline.max_hp)

	var tanky: Combatant = MinionLibrary.make(true)
	_check(tanky.max_hp == 25, "tanky (crit-summoned) minion max_hp = 25 (got %d)" % tanky.max_hp)
	_check(tanky.max_hp > baseline.max_hp, "tanky minion has more HP than baseline")

	print(("MINION LIBRARY TEST PASSED" if _failures == 0 else "MINION LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
