extends SceneTree

# Headless unit test for TurnManager (DESIGN.md §4.1 turn order).
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_turn_manager.gd

var _failures: int = 0
var _turn_order_log: Array[String] = []
var _round_log: Array[int] = []
var _combat_ended_winner_is_player: int = -1  # -1 = not fired, 0/1 = bool

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _on_turn_started(c: Combatant) -> void:
	_turn_order_log.append(c.display_name)

func _on_round_started(n: int) -> void:
	_round_log.append(n)

func _on_combat_ended(winner_is_player: bool) -> void:
	_combat_ended_winner_is_player = 1 if winner_is_player else 0

func _mk(name: String, is_player: bool, init: int = 0, max_hp: int = 20) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.is_player = is_player
	c.max_hp = max_hp
	c.start_combat()
	# Sets current_initiative directly for the turn-ORDER tests (B/D/E) only — base_initiative is
	# intentionally left at 0 here. These are controlled sort-key values, NOT the roll path, so the
	# derived-initiative invariant (current == base + mods) does NOT hold for _mk-built combatants.
	c.current_initiative = init
	return c

func _initialize() -> void:
	# --- A. Initiative rolls land in 1..100 ---
	var tm: TurnManager = TurnManager.new()
	tm.combatants = [_mk("P", true), _mk("E", false)]
	var out_of_range: int = 0
	for i: int in range(300):
		tm.roll_initiative()
		for c: Combatant in tm.combatants:
			if c.current_initiative < 1 or c.current_initiative > 100:
				out_of_range += 1
			if c.base_initiative != c.current_initiative:
				out_of_range += 1  # with no effects, current must equal base
	_check(out_of_range == 0, "all initiative rolls in 1..100 (out-of-range: %d)" % out_of_range)

	# --- B. get_turn_order() sorts by current_initiative descending ---
	var tm2: TurnManager = TurnManager.new()
	tm2.combatants = [_mk("mid", true, 55), _mk("hi", false, 80), _mk("lo", true, 30)]
	var order: Array = tm2.get_turn_order()
	var names: Array[String] = []
	for c: Combatant in order:
		names.append(c.display_name)
	_check(names == ["hi", "mid", "lo"], "turn order desc by initiative: %s" % str(names))

	# --- C. combat-end detection by side ---
	var tm3: TurnManager = TurnManager.new()
	var p3: Combatant = _mk("P", true, 50)
	var e3: Combatant = _mk("E", false, 40)
	tm3.combatants = [p3, e3]
	_check(not tm3.is_combat_over(), "both sides alive -> not over")
	e3.take_damage(999)
	_check(tm3.is_combat_over(), "enemy dead -> combat over")
	_check(tm3.winner_is_player(), "winner is player when only players remain")

	# --- D. begin()/advance_turn() sequences turns and rolls into new rounds ---
	var tm4: TurnManager = TurnManager.new()
	tm4.combatants = [_mk("P", true, 90), _mk("E", false, 40)]
	tm4.round_started.connect(_on_round_started)
	tm4.turn_started.connect(_on_turn_started)
	tm4.combat_ended.connect(_on_combat_ended)
	tm4.begin()
	tm4.advance_turn()  # -> enemy
	tm4.advance_turn()  # -> new round, player again
	_check(_round_log == [1, 2], "rounds started in order: %s" % str(_round_log))
	_check(_turn_order_log == ["P", "E", "P"], "turn sequence P,E,P across rounds: %s" % str(_turn_order_log))

	# --- E. advancing into a finished combat emits combat_ended with the winner ---
	var tm5: TurnManager = TurnManager.new()
	var p5: Combatant = _mk("Hero", true, 90)
	var e5: Combatant = _mk("Rat", false, 40)
	tm5.combatants = [p5, e5]
	tm5.combat_ended.connect(_on_combat_ended)
	tm5.begin()            # Hero's turn
	e5.take_damage(999)    # Hero kills the rat
	tm5.advance_turn()     # should end combat, player wins
	_check(_combat_ended_winner_is_player == 1, "combat_ended fired with player win (got %d)" % _combat_ended_winner_is_player)

	# --- is_minion combatants are excluded from _living()'s win/loss gate, same as is_target_dummy ---
	var minion_tm: TurnManager = TurnManager.new()
	var pc_side: Combatant = _mk("PC", true, 0, 10)
	var enemy_side: Combatant = _mk("Enemy", false, 0, 10)
	var lone_minion: Combatant = _mk("Minion", true, 0, 10)
	lone_minion.is_minion = true
	minion_tm.combatants = [pc_side, enemy_side, lone_minion]
	pc_side.take_damage(999)  # kill the only real PC
	_check(minion_tm.is_combat_over(), "combat is over when the only real PC dies, even if an is_minion combatant on the same side survives")
	_check(not minion_tm.winner_is_player(), "the surviving minion does NOT count as a player win")

	# --- roll_initiative_for() rolls exactly one combatant, independent of the others ---
	var extract_tm: TurnManager = TurnManager.new()
	var solo: Combatant = _mk("Solo", true, 0, 10)
	extract_tm.combatants = [solo]
	var solo_value: int = extract_tm.roll_initiative_for(solo)
	_check(solo_value >= 1 and solo_value <= 100, "roll_initiative_for returns a value in 1..100 (got %d)" % solo_value)
	_check(solo.current_initiative != 0, "roll_initiative_for actually sets the combatant's current_initiative")

	# --- roll_initiative() still behaves identically after the refactor (no regression) ---
	var regress_tm: TurnManager = TurnManager.new()
	var r1: Combatant = _mk("R1", true, 0, 10)
	var r2: Combatant = _mk("R2", false, 0, 10)
	regress_tm.combatants = [r1, r2]
	regress_tm.roll_initiative()
	_check(r1.current_initiative != 0 and r2.current_initiative != 0, "roll_initiative() still rolls every combatant after the refactor")

	# --- Finding 1 (2026-08-17 final-review fix): a minion killed via a path that does NOT call
	# remove_dead_combatant() directly (e.g. an ordinary enemy attack landing the killing blow, or
	# Combatant.fire_grand_sacrifice()'s self-inflicted take_damage) must still be pruned from turn
	# order by the very next round boundary, not linger permanently on the TurnOrderBar. Simulated
	# here via a direct take_damage() call — no remove_dead_combatant() call at all — followed by
	# begin(), which runs _start_next_round()'s new _prune_dead_minions() sweep.
	var prune_tm: TurnManager = TurnManager.new()
	var prune_pc: Combatant = _mk("PC2", true, 60, 20)
	var prune_enemy: Combatant = _mk("Enemy2", false, 50, 20)
	var prune_minion: Combatant = _mk("DeadMinion", true, 55, 10)
	prune_minion.is_minion = true
	prune_tm.combatants = [prune_pc, prune_enemy, prune_minion]
	prune_minion.take_damage(999)  # killed directly -- NOT via remove_dead_combatant()
	_check(prune_tm.combatants.has(prune_minion), "sanity: the dead minion is still in combatants before any round boundary runs")
	prune_tm.begin()  # round 1 -- _start_next_round() should already have pruned it
	_check(not prune_tm.combatants.has(prune_minion), "dead minion pruned from combatants at the very next round boundary (begin())")
	var order_names: Array[String] = []
	for c: Combatant in prune_tm.get_turn_order():
		order_names.append(c.display_name)
	_check(not order_names.has("DeadMinion"), "dead minion absent from get_turn_order()'s result too (got %s)" % str(order_names))

	print(("TURN MANAGER TEST PASSED" if _failures == 0 else "TURN MANAGER TEST FAILED: %d" % _failures))
	quit(_failures)
