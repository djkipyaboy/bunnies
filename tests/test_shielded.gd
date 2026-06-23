extends SceneTree

# Headless test: SHIELDED absorb in take_damage, higher-total-overrides apply rule, turn tick. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shielded.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(max_hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.max_hp = max_hp
	c.hp = max_hp
	return c

func _initialize() -> void:
	# User's worked example: 300 HP + 10 shield, struck for 20 -> shield eats 10, HP takes 10 -> 290, shield gone.
	var c: Combatant = _mk(300)
	c.apply_shield(10, 2)
	_check(c.shield_hp == 10, "shield applied 10 (got %d)" % c.shield_hp)
	c.take_damage(20)
	_check(c.hp == 290, "HP 300 -> 290 after 10 absorbed (got %d)" % c.hp)
	_check(c.shield_hp == 0, "shield fully spent (got %d)" % c.shield_hp)
	_check(c.shield_turns == 0, "shield turns cleared when hp hits 0 (got %d)" % c.shield_turns)

	# Partial absorb: damage less than shield leaves HP untouched.
	var d: Combatant = _mk(300)
	d.apply_shield(50, 2)
	d.take_damage(20)
	_check(d.hp == 300, "HP untouched while shield absorbs (got %d)" % d.hp)
	_check(d.shield_hp == 30, "shield 50 -> 30 (got %d)" % d.shield_hp)

	# Higher-total-overrides: a smaller new shield is ignored; a bigger one replaces.
	var e: Combatant = _mk(300)
	e.apply_shield(30, 2)
	e.apply_shield(10, 5)
	_check(e.shield_hp == 30 and e.shield_turns == 2, "smaller shield ignored (got hp %d turns %d)" % [e.shield_hp, e.shield_turns])
	e.apply_shield(50, 1)
	_check(e.shield_hp == 50 and e.shield_turns == 1, "bigger shield overrides (got hp %d turns %d)" % [e.shield_hp, e.shield_turns])

	# Turn tick: a 2-turn shield clears after two on_end ticks.
	var f: Combatant = _mk(300)
	f.apply_shield(40, 2)
	f.on_end()
	_check(f.shield_hp == 40 and f.shield_turns == 1, "after 1 tick: 40 hp, 1 turn (got hp %d turns %d)" % [f.shield_hp, f.shield_turns])
	f.on_end()
	_check(f.shield_hp == 0 and f.shield_turns == 0, "after 2 ticks: shield expired (got hp %d turns %d)" % [f.shield_hp, f.shield_turns])

	print(("SHIELDED TEST PASSED" if _failures == 0 else "SHIELDED TEST FAILED: %d" % _failures))
	quit(_failures)
