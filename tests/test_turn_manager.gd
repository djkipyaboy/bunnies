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

	print(("TURN MANAGER TEST PASSED" if _failures == 0 else "TURN MANAGER TEST FAILED: %d" % _failures))
	quit(_failures)
