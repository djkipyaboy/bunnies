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
	_check(not baseline.acts_last, "baseline minion acts_last = false (sorts into turn order purely by its own rolled initiative, playtest 2026-08-16)")
	_check(baseline.weapon == null, "baseline minion has no weapon (weaponless, like a target dummy)")
	_check(baseline.is_alive(), "baseline minion starts alive")
	_check(baseline.max_hp == 15, "baseline minion max_hp = 15 (got %d)" % baseline.max_hp)

	var tanky: Combatant = MinionLibrary.make(true)
	_check(tanky.max_hp == 25, "tanky (crit-summoned) minion max_hp = 25 (got %d)" % tanky.max_hp)
	_check(tanky.max_hp > baseline.max_hp, "tanky minion has more HP than baseline")

	var dew: Combatant = MinionLibrary.make(false, &"dew")
	_check(dew.minion_type == &"dew", "MinionLibrary.make(false, &dew) sets minion_type = &dew (got %s)" % dew.minion_type)
	_check(dew.display_name == "Dew Minion", "dew minion display name is 'Dew Minion' (got %s)" % dew.display_name)
	_check(dew.is_minion and dew.is_player, "dew minion is still is_minion/is_player like every other type")

	var misfortune: Combatant = MinionLibrary.make(false, &"misfortune")
	_check(misfortune.minion_type == &"misfortune", "misfortune minion_type set correctly (got %s)" % misfortune.minion_type)
	_check(misfortune.display_name == "Misfortune Minion", "misfortune display name correct (got %s)" % misfortune.display_name)

	var hasty: Combatant = MinionLibrary.make(false, &"hasty")
	_check(hasty.minion_type == &"hasty", "hasty minion_type set correctly (got %s)" % hasty.minion_type)
	_check(hasty.display_name == "Hasty Minion", "hasty display name correct (got %s)" % hasty.display_name)

	# Backward-compat: the default-argument call (used by the already-shipped Ember summon path)
	# still produces an Ember minion with no changes to its own behavior.
	var default_call: Combatant = MinionLibrary.make(false)
	_check(default_call.minion_type == &"ember", "make(tanky) with no type arg still defaults to &ember (got %s)" % default_call.minion_type)
	_check(default_call.display_name == "Ember Minion", "default-call display name unchanged (got %s)" % default_call.display_name)

	print(("MINION LIBRARY TEST PASSED" if _failures == 0 else "MINION LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
