extends SceneTree

# Headless test: the item-use heal formula (2026-07-16 combat item-use targeting design §2/§3.5) —
# SUCCESS heals the base amount unchanged; CRIT_SUCCESS heals ceil(base * 1.5). Pure formula check,
# no reel spin involved (mirrors tests/test_rallying_cry.gd's per-tier shield-formula section).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_heal.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# base_heal = 25 (Healing Potion's [ASSUMPTION] value, spec §3.7's example).
	var base_heal: int = 25
	_check(ceili(base_heal * 1.0) == 25, "SUCCESS heals the base amount unchanged (got %d)" % ceili(base_heal * 1.0))
	_check(ceili(base_heal * 1.5) == 38, "CRIT_SUCCESS heals ceil(25 * 1.5) = 38 (got %d)" % ceili(base_heal * 1.5))

	# An odd base amount proves the ceil (round-up) behavior actually matters, not a coincidental exact int.
	var odd_base: int = 11
	_check(ceili(odd_base * 1.5) == 17, "CRIT_SUCCESS rounds UP: ceil(11 * 1.5) = ceil(16.5) = 17 (got %d)" % ceili(odd_base * 1.5))

	# Applying the formula through Combatant.heal() on a damaged ally.
	# Note: Combatant.heal() returns the OVERFLOW (excess beyond max HP), not the amount restored —
	# see tests/test_heal.gd / tests/test_big_bang.gd / the 2026-06-27 Seer spec ("clamps to max and
	# returns the overflow"). Since 40 + 38 = 78 stays under the 100 cap, overflow is 0 here.
	var ally: Combatant = Combatant.new()
	ally.base_max_hp = 100
	ally.apply_stats()
	ally.start_combat()
	ally.take_damage(60)  # 40/100 hp
	var overflow: int = ally.heal(ceili(base_heal * 1.5))
	_check(overflow == 0, "heal() returns 0 overflow (fully absorbed under the cap, got %d)" % overflow)
	_check(ally.hp == 78, "ally hp rises by the crit heal amount (40 + 38 = 78, got %d)" % ally.hp)

	print(("ITEM USE HEAL TEST PASSED" if _failures == 0 else "ITEM USE HEAL TEST FAILED: %d" % _failures))
	quit(_failures)
