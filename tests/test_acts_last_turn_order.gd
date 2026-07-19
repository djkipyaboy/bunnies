extends SceneTree

## Headless test: acts_last combatants always sort after every non-acts_last combatant in
## TurnManager.get_turn_order(), regardless of initiative (spec 2026-07-19 §3.1) — and
## insert_acting_this_round() appends a combatant into the round already in progress.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make(name: String, initiative: int, acts_last: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.base_stats = Stats.new()
	c.base_max_hp = 10
	c.apply_stats()
	c.start_combat()
	c.current_initiative = initiative
	c.acts_last = acts_last
	return c

func _initialize() -> void:
	var tm: TurnManager = TurnManager.new()
	var fast: Combatant = _make("Fast", 90, false)
	var slow_acts_last: Combatant = _make("SlowActsLast", 5, true)
	var slow: Combatant = _make("Slow", 10, false)
	var fast_acts_last: Combatant = _make("FastActsLast", 95, true)
	tm.combatants = [slow_acts_last, fast, slow, fast_acts_last]
	var order: Array[Combatant] = tm.get_turn_order()
	_check(order[0] == fast, "the highest-initiative NON-acts_last combatant goes first")
	_check(order[1] == slow, "the next NON-acts_last combatant goes second")
	_check(order[2] == fast_acts_last or order[2] == slow_acts_last, "an acts_last combatant is 3rd")
	_check(order[3] == fast_acts_last or order[3] == slow_acts_last, "an acts_last combatant is 4th")
	_check(order.find(fast) < order.find(fast_acts_last), "fast_acts_last (init 95) still sorts AFTER fast (init 90) despite higher initiative")
	_check(order.find(fast_acts_last) < order.find(slow_acts_last), "between two acts_last combatants, higher initiative (95 vs 5) still wins the tie")

	# insert_acting_this_round: a combatant joining mid-round must act THIS round.
	tm.combatants = [fast, slow]
	tm.begin()
	var newcomer: Combatant = _make("Newcomer", 999, true)
	tm.insert_acting_this_round(newcomer)
	_check(tm.combatants.has(newcomer), "insert_acting_this_round adds the combatant to .combatants")
	# Drain the round: fast, slow, newcomer should each get a turn before a new round starts.
	var seen: Array[Combatant] = []
	var round_before: int = tm.round_number
	for i in range(3):
		seen.append(tm._order[tm._turn_index])
		tm.advance_turn()
	_check(newcomer in seen, "the newly-inserted combatant took a turn in the SAME round it joined")
	_check(tm.round_number == round_before, "no new round started while draining the 3 acting members")

	print(("ACTS_LAST TURN ORDER TEST PASSED" if _failures == 0 else "ACTS_LAST TURN ORDER TEST FAILED: %d" % _failures))
	quit(_failures)
