extends SceneTree

# Headless test for the Summoner Bonus Meter economy fix (2026-08-18, following the 2026-08-18
# playtest note on the Summoner's meter rarely reaching cap): three new flat charge sources layered
# on top of the existing minion-summon/minion-lifecycle/Grand-Sacrifice code paths in combat.gd/
# combatant.gd — a reduced charge on every summon-ability cast (make_summon_reel() itself stays
# charges_meter = false; this is a separate, smaller, flat award), a bonus when a minion completes
# its stage-3 expiry naturally, and a bonus when Grand Sacrifice consumes a minion. None of these
# touch BonusMeter.resolve_post_combat()'s floor/cap formula itself.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_meter_economy.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_summoner() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.bonus_meter.cap = 15
	c.bonus_meter.value = 0
	c.begin_turn()
	return c

## Wires a real Combat instance's minimal state so _finish_spin()'s summon-payoff branch and
## _run_minion_stage() run for real. Mirrors tests/test_grand_sacrifice.gd's _build_combat().
func _build_combat(pc: Combatant, enemies: Array[Combatant]) -> Combat:
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst._pcs = [pc]
	inst._enemies = enemies
	inst._dummies = []
	var all: Array[Combatant] = [pc]
	all.append_array(enemies)
	inst._turn_manager.combatants = all
	for c: Combatant in all:
		inst._panels[c] = CombatantPanel.new()
	inst._attacker = pc
	inst._defender = enemies[0] if enemies.size() > 0 else null
	inst._plan = MainPhasePlan.new(pc, pc.ability_cost, 5, 2)
	return inst

func _free_combat(inst: Combat) -> void:
	inst.queue_free()
	await process_frame

# --- Summoning a minion sets minion_caster AND awards the reduced flat charge ---
func _run_summon_cast_charges_meter_and_sets_caster() -> void:
	var pc: Combatant = _make_summoner()
	var enemy: Combatant = Combatant.new(); enemy.base_max_hp = 300; enemy.apply_stats(); enemy.start_combat()
	var inst: Combat = await _build_combat(pc, [enemy])

	pc.apply_summon_minion(pc.ability_cost, 5)  # base ability: stages the Ember Minion summon_reel
	inst._summon_tier = ReelFace.ResultTier.SUCCESS  # force a baseline (non-crit) summon result
	inst._apply_minion_summon_payoff(pc, ReelFace.ResultTier.SUCCESS)

	_check(pc.active_minion != null and pc.active_minion.is_alive(), "sanity: a minion was summoned")
	_check(pc.active_minion.minion_caster == pc, "the summoned minion's minion_caster points back to its summoner")
	_check(pc.bonus_meter.value == Combat.SUMMON_CAST_BM_CHARGE, "summoning charges the caster's meter by the reduced flat amount (got %d, want %d)" % [pc.bonus_meter.value, Combat.SUMMON_CAST_BM_CHARGE])

	await _free_combat(inst)

func _initialize() -> void:
	await _run_summon_cast_charges_meter_and_sets_caster()

	print(("SUMMONER METER ECONOMY TEST PASSED" if _failures == 0 else "SUMMONER METER ECONOMY TEST FAILED: %d" % _failures))
	quit(_failures)
