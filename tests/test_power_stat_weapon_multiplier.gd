extends SceneTree

# Headless test: power_stat_weapon_multiplier() and its fold into outgoing_damage_multiplier()
# (design spec 2026-08-28 §2.2). Might-power classes must stay EXACTLY neutral (regression); any
# other power stat gets the new StatScaling curve.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_weapon_multiplier.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Might-power combatant, ANY Might value -> exactly 1.0 (Might's own damage path is untouched;
	# this is a regression guard for every existing melee/ranged combatant).
	var might_c: Combatant = Combatant.new()
	might_c.power_stat = &"might"
	var ms: Stats = Stats.new(); ms.might = 6
	might_c.base_stats = ms
	_check(might_c.power_stat_weapon_multiplier() == 1.0, "Might power_stat -> weapon multiplier stays 1.0 (got %f)" % might_c.power_stat_weapon_multiplier())
	_check(might_c.outgoing_damage_multiplier() == 1.0, "outgoing_damage_multiplier unaffected for a Might-power combatant with no other effects (got %f)" % might_c.outgoing_damage_multiplier())

	# Focus-power combatant with Focus 4 -> StatScaling.multiplier(4) = 1.5, and that flows through
	# outgoing_damage_multiplier() since no other multiplier effects are active.
	var focus_c: Combatant = Combatant.new()
	focus_c.power_stat = &"focus"
	var fs: Stats = Stats.new(); fs.focus = 4
	focus_c.base_stats = fs
	_check(is_equal_approx(focus_c.power_stat_weapon_multiplier(), 1.5), "Focus 4 power_stat -> weapon multiplier 1.5 (got %f)" % focus_c.power_stat_weapon_multiplier())
	_check(is_equal_approx(focus_c.outgoing_damage_multiplier(), 1.5), "outgoing_damage_multiplier includes the Focus curve (got %f)" % focus_c.outgoing_damage_multiplier())

	# 0 Focus -> neutral, same as Might's baseline (no regression for an un-invested caster).
	var zero_focus: Combatant = Combatant.new()
	zero_focus.power_stat = &"focus"
	_check(zero_focus.power_stat_weapon_multiplier() == 1.0, "0 Focus -> 1.0 (got %f)" % zero_focus.power_stat_weapon_multiplier())

	print(("POWER STAT WEAPON MULTIPLIER TEST PASSED" if _failures == 0 else "POWER STAT WEAPON MULTIPLIER TEST FAILED: %d" % _failures))
	quit(_failures)
