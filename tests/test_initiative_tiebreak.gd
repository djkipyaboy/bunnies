extends SceneTree

# Headless test: initiative tie-break order = current_initiative -> Finesse -> tiebreak_roll.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_initiative_tiebreak.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(name: String, init: int, finesse: int, tb: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.base_stats = Stats.new(); c.base_stats.finesse = finesse
	c.current_initiative = init
	c.tiebreak_roll = tb
	return c

func _names(order: Array) -> Array:
	var out: Array = []
	for c: Combatant in order: out.append(c.display_name)
	return out

func _initialize() -> void:
	var tm: TurnManager = TurnManager.new()

	# Equal current_initiative -> higher Finesse acts first.
	tm.combatants = [_mk("lowFin", 50, 1, 5), _mk("highFin", 50, 4, 5)]
	_check(_names(tm.get_turn_order()) == ["highFin", "lowFin"], "tie broken by Finesse: %s" % str(_names(tm.get_turn_order())))

	# Equal current_initiative + equal Finesse -> higher tiebreak_roll first.
	tm.combatants = [_mk("lowRoll", 50, 2, 3), _mk("highRoll", 50, 2, 9)]
	_check(_names(tm.get_turn_order()) == ["highRoll", "lowRoll"], "tie broken by tiebreak_roll: %s" % str(_names(tm.get_turn_order())))

	# Higher current_initiative still wins regardless of finesse/roll.
	tm.combatants = [_mk("fast", 80, 0, 0), _mk("slow", 30, 9, 9)]
	_check(_names(tm.get_turn_order()) == ["fast", "slow"], "current_initiative dominates")

	# roll_initiative folds Finesse into base_initiative and sets a tiebreak_roll in 0..9.
	var tm2: TurnManager = TurnManager.new()
	var hero: Combatant = Combatant.new(); hero.base_stats = Stats.new(); hero.base_stats.finesse = 5
	tm2.combatants = [hero]
	tm2.roll_initiative()
	_check(hero.base_initiative >= 1 + 5 and hero.base_initiative <= 100 + 5, "finesse folded into base_initiative (got %d)" % hero.base_initiative)
	_check(hero.current_initiative == hero.base_initiative, "current == base after roll (no effects)")
	_check(hero.tiebreak_roll >= 0 and hero.tiebreak_roll <= 9, "tiebreak_roll in 0..9 (got %d)" % hero.tiebreak_roll)

	print(("INITIATIVE TIEBREAK TEST PASSED" if _failures == 0 else "INITIATIVE TIEBREAK TEST FAILED: %d" % _failures))
	quit(_failures)
