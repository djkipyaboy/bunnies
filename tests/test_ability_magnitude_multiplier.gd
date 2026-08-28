extends SceneTree

# Headless test: ability_magnitude_multiplier() (design spec 2026-08-28 §2.2/§1.2) — unlike
# power_stat_weapon_multiplier(), this scales for EVERY power stat including Might.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_magnitude_multiplier.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Might power_stat with Might 4 -> StatScaling.multiplier(4) = 1.5 (NOT 1.0 — this is the
	# key difference from power_stat_weapon_multiplier(), which stays neutral for Might).
	var might_c: Combatant = Combatant.new()
	might_c.power_stat = &"might"
	var ms: Stats = Stats.new(); ms.might = 4
	might_c.base_stats = ms
	_check(is_equal_approx(might_c.ability_magnitude_multiplier(), 1.5), "Might 4 ability magnitude multiplier -> 1.5 (got %f)" % might_c.ability_magnitude_multiplier())

	# Focus power_stat with Focus 4 -> also 1.5 (same curve, different source stat).
	var focus_c: Combatant = Combatant.new()
	focus_c.power_stat = &"focus"
	var fs: Stats = Stats.new(); fs.focus = 4
	focus_c.base_stats = fs
	_check(is_equal_approx(focus_c.ability_magnitude_multiplier(), 1.5), "Focus 4 ability magnitude multiplier -> 1.5 (got %f)" % focus_c.ability_magnitude_multiplier())

	# 0 power stat -> neutral 1.0 (no ability-magnitude change for an un-invested character).
	var zero_c: Combatant = Combatant.new()
	_check(zero_c.ability_magnitude_multiplier() == 1.0, "0 power stat -> 1.0 (got %f)" % zero_c.ability_magnitude_multiplier())

	print(("ABILITY MAGNITUDE MULTIPLIER TEST PASSED" if _failures == 0 else "ABILITY MAGNITUDE MULTIPLIER TEST FAILED: %d" % _failures))
	quit(_failures)
