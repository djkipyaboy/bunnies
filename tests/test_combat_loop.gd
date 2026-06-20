extends SceneTree

# Headless INTEGRATION test: drives the full loop through the real managers/resolver/combatants
# (the same wiring combat.gd uses, minus animation) and confirms a fight runs to a winner.
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_combat_loop.gd

var _failures: int = 0
var _turns: int = 0
var _done: bool = false
var _winner_is_player: int = -1
var _winner: Combatant

var _tm: TurnManager
var _resolver: CombatResolver
var _pc: Combatant
var _enemy: Combatant

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk(name: String, is_player: bool, max_hp: int, defense: DamageType, base: float, type: DamageType, reels: int) -> Combatant:
	var w: Weapon = Weapon.new()
	w.base_damage = base
	for i: int in range(reels):
		w.reels.append(ActionReel.make_default(type))
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.is_player = is_player
	c.max_hp = max_hp
	c.defense_type = defense
	c.weapon = w
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 10
	c.bonus_meter.floor = 3
	c.start_combat()
	return c

func _on_turn_started(c: Combatant) -> void:
	if _done:
		return
	_turns += 1
	if _turns > 200:
		_check(false, "loop terminated within 200 turns")
		_done = true
		return
	var defender: Combatant = _enemy if c == _pc else _pc
	c.on_upkeep()
	c.begin_turn()
	var attacks: Array = _resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, defender.defense_type, c.wild_reel_indices(), c.weapon.reels.size(), c.effective_stats().might)
	c.consume_wild_spin()
	for a in attacks:
		defender.take_damage(a.final_damage)
		c.bonus_meter.charge(a.face.result_tier)
		if a.rider_effect_id != &"":
			defender.attach_effect(EffectLibrary.make(a.rider_effect_id))
	c.on_end()
	_tm.advance_turn()

func _on_combat_ended(winner_is_player: bool) -> void:
	_done = true
	_winner_is_player = 1 if winner_is_player else 0
	_winner = _pc if winner_is_player else _enemy

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")

	# Type chart sanity: Slashing → Earth defender is the ×1.25 matchup we rely on.
	_check(is_equal_approx(slashing.multiplier_against(earth), 1.25), "Slashing vs Earth = 1.25")

	_resolver = CombatResolver.new()
	_pc = _mk("Martin", true, 40, slashing, 10.0, slashing, 3)
	_enemy = _mk("Rat", false, 30, earth, 8.0, crushing, 2)

	_tm = TurnManager.new()
	_tm.combatants = [_pc, _enemy]
	_tm.turn_started.connect(_on_turn_started)
	_tm.combat_ended.connect(_on_combat_ended)

	_tm.roll_initiative()
	_tm.begin()  # synchronous chain: turns resolve until one side falls

	_check(_done, "combat reached a conclusion")
	_check(_winner_is_player != -1, "combat_ended fired with a winner")
	_check(not (_pc.is_alive() and _enemy.is_alive()), "exactly one side survives")
	var loser_dead: bool = (_pc.hp == 0) != (_enemy.hp == 0)
	_check(loser_dead, "the loser is at 0 HP (pc=%d, enemy=%d)" % [_pc.hp, _enemy.hp])
	_check(_winner_is_player == (1 if _pc.is_alive() else 0), "winner flag matches who survived")
	# The winner must have landed damaging hits to win, so its meter charged (success/crit give meter).
	_check(_winner != null and _winner.bonus_meter.value > 0, "winner's Bonus Meter charged (value=%d)" % (_winner.bonus_meter.value if _winner else -1))
	_check(_turns >= 1 and _turns <= 200, "fight ran a bounded number of turns (%d)" % _turns)

	print(("COMBAT LOOP TEST PASSED" if _failures == 0 else "COMBAT LOOP TEST FAILED: %d" % _failures))
	quit(_failures)
