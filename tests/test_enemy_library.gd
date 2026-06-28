extends SceneTree

# Headless test: EnemyLibrary — the 3 created enemy characters (spec 2026-06-29-nvm-party-combat §5.1).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(EnemyLibrary.IDS.size() == 3, "3 enemies registered (got %d)" % EnemyLibrary.IDS.size())
	_check(EnemyLibrary.IDS == [&"rat", &"ferret", &"stoat"], "ids = rat/ferret/stoat")

	# Labels (cheap, no Combatant built).
	_check(EnemyLibrary.label(&"rat") == "Cluny's Rat", "rat label")
	_check(EnemyLibrary.label(&"ferret") == "Redtooth (Ferret)", "ferret label")
	_check(EnemyLibrary.label(&"stoat") == "Killconey (Stoat)", "stoat label")

	# Each builds a live, enemy-side combatant with a hidden meter and the right reel count.
	var rat: Combatant = EnemyLibrary.make(&"rat")
	_check(rat.is_alive() and not rat.is_player, "rat is a live enemy")
	_check(rat.weapon.reels.size() == 2, "rat has 2 reels")
	_check(not rat.bonus_meter.is_visible, "rat meter hidden")
	_check(rat.max_hp == 300, "rat HP 300 (got %d)" % rat.max_hp)

	var ferret: Combatant = EnemyLibrary.make(&"ferret")
	_check(ferret.weapon.reels.size() == 3, "ferret has 3 reels")

	var stoat: Combatant = EnemyLibrary.make(&"stoat")
	_check(stoat.weapon.reels.size() == 4, "stoat has 4 reels")

	# Distinct fresh instances (no shared state).
	_check(EnemyLibrary.make(&"rat") != rat, "make returns a fresh instance each call")
	_check(EnemyLibrary.make(&"nope") == null, "unknown id -> null")

	print(("ENEMY LIBRARY TEST PASSED" if _failures == 0 else "ENEMY LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
