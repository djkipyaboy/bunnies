extends SceneTree

# Headless test for the Summoner's "Grand Sacrifice" Ultimate (2026-08-16 summoner-ability-kit
# spec §8): consumes the Bonus Meter AND requires an active, alive minion (sacrificed as the cost —
# self-inflicted fatal damage, the same expiry pattern used everywhere else a minion is
# replaced/expires), then applies one of 4 variants keyed on the SACRIFICED minion's own
# minion_type (not whichever ability was most recently pressed).
#
# Modeled on the "Dark Reinforcements" precedent (combat.gd/combatant.gd: an instant Ultimate with
# no reel/spin component) for firing, and the Warden Acolyte "curse the party" pending-flag pattern
# (heal_boss_pending/curse_party_pending) for how the orchestrator applies an effect that needs
# enemy/ally target lists Combatant itself doesn't have — see grand_sacrifice_variant_pending.
#
# Builds a lightweight, manually-wired Combat instance (mirrors tests/test_enemy_ultimate_firing.gd)
# rather than driving a full CombatHandoff/real-spin harness — firing the Ultimate is instant at
# _commit_main1() time, no spin needed.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## A Summoner PC with ultimate_id = grand_sacrifice, an armed meter (unless [param meter_armed] is
## false), and (unless [param minion_type] is &"") a real active_minion of that type.
func _make_summoner(minion_type: StringName, meter_armed: bool = true) -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.ultimate_id = &"grand_sacrifice"
	c.bonus_meter.cap = 15
	c.bonus_meter.value = 15 if meter_armed else 0
	c.begin_turn()
	if minion_type != &"":
		c.active_minion = MinionLibrary.make(false, minion_type)
	return c

## Wires a real Combat instance's minimal state so _commit_main1() (and everything it calls —
## _apply_grand_sacrifice, _splash_half_to_others, _allies_of/_enemies_of) runs for real, without
# driving a full turn/spin. Mirrors test_enemy_ultimate_firing.gd's manual-wiring technique.
func _build_combat(pc: Combatant, extra_allies: Array[Combatant], enemies: Array[Combatant]) -> Combat:
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	var pcs: Array[Combatant] = [pc]
	pcs.append_array(extra_allies)
	inst._pcs = pcs
	inst._enemies = enemies
	inst._dummies = []
	var all: Array[Combatant] = pcs.duplicate()
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

# --- Cannot stage without an active minion, even with a full meter ---
func _run_cannot_stage_without_minion() -> void:
	var pc: Combatant = _make_summoner(&"", true)  # meter armed, NO minion
	var plan: MainPhasePlan = MainPhasePlan.new(pc, pc.ability_cost, 5, 2)
	_check(pc.bonus_meter.is_armed(), "sanity: meter is armed")
	_check(not plan.can_stage_ultimate(), "cannot stage Grand Sacrifice with a full meter but no active minion")

# --- Can stage once a minion IS active AND the meter is full ---
func _run_can_stage_with_minion_and_meter() -> void:
	var pc: Combatant = _make_summoner(&"ember", true)
	var plan: MainPhasePlan = MainPhasePlan.new(pc, pc.ability_cost, 5, 2)
	_check(plan.can_stage_ultimate(), "can stage Grand Sacrifice with an active, alive minion AND an armed meter")

	# A dead minion (still assigned to active_minion) must not satisfy the precondition either.
	pc.active_minion.take_damage(pc.active_minion.hp)
	_check(not pc.active_minion.is_alive(), "sanity: the minion is now dead")
	_check(not plan.can_stage_ultimate(), "cannot stage Grand Sacrifice once the active_minion has died")

# --- Firing consumes the meter AND kills the active minion (take_damage(hp)) ---
func _run_firing_consumes_meter_and_minion() -> void:
	var pc: Combatant = _make_summoner(&"ember", true)
	var minion: Combatant = pc.active_minion
	var plan: MainPhasePlan = MainPhasePlan.new(pc, pc.ability_cost, 5, 2)
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Grand Sacrifice staged via the real toggle_ultimate()")
	plan.commit()
	_check(pc.bonus_meter.value == 0, "firing Grand Sacrifice consumes the full meter")
	_check(not minion.is_alive(), "firing Grand Sacrifice kills the sacrificed minion")
	_check(pc.active_minion == null, "active_minion is cleared after the sacrifice")
	_check(pc.grand_sacrifice_variant_pending == &"ember", "grand_sacrifice_variant_pending is set to the sacrificed minion's own type (ember)")

# --- Ember variant: burst damage to the primary target + 50% splash to every other enemy ---
func _run_ember_variant() -> void:
	var pc: Combatant = _make_summoner(&"ember", true)
	var enemy1: Combatant = Combatant.new(); enemy1.base_max_hp = 300; enemy1.apply_stats(); enemy1.start_combat()
	var enemy2: Combatant = Combatant.new(); enemy2.base_max_hp = 300; enemy2.apply_stats(); enemy2.start_combat()
	var inst: Combat = await _build_combat(pc, [], [enemy1, enemy2])

	var hp1_before: int = enemy1.hp
	var hp2_before: int = enemy2.hp
	inst._plan.toggle_ultimate()
	inst._commit_main1()

	_check(pc.bonus_meter.value == 0, "ember: meter consumed")
	_check(enemy1.hp == hp1_before - Combat.GRAND_SACRIFICE_EMBER_BURST, "ember: primary target takes the full burst (%d)" % Combat.GRAND_SACRIFICE_EMBER_BURST)
	var expected_splash: int = ceili(Combat.GRAND_SACRIFICE_EMBER_BURST * 0.5)
	_check(enemy2.hp == hp2_before - expected_splash, "ember: the OTHER enemy takes 50%% splash (%d)" % expected_splash)
	_check(pc.grand_sacrifice_variant_pending == &"", "ember: pending flag cleared after application")

	await _free_combat(inst)

# --- Dew variant: large AoE heal + improved Thorns + a repeating per-turn cleanse for 2 turns ---
func _run_dew_variant() -> void:
	var pc: Combatant = _make_summoner(&"dew", true)
	pc.take_damage(50)  # so the heal is observable
	var weakened: Effect = EffectLibrary.make(&"weakened")
	pc.attach_effect(weakened)
	_check(pc.has_effect(&"weakened"), "dew setup: caster carries a debuff before the cast")
	var enemy: Combatant = Combatant.new(); enemy.base_max_hp = 300; enemy.apply_stats(); enemy.start_combat()
	var inst: Combat = await _build_combat(pc, [], [enemy])

	var hp_before: int = pc.hp
	inst._plan.toggle_ultimate()
	inst._commit_main1()

	_check(pc.hp == mini(hp_before + Combat.GRAND_SACRIFICE_DEW_HEAL, pc.max_hp), "dew: caster healed by the large AoE heal amount")
	_check(pc.thorns_pct() >= Combat.GRAND_SACRIFICE_DEW_THORNS_PCT, "dew: improved Thorns is bigger than the base Dew Minion's 0.20 (got %f)" % pc.thorns_pct())
	# The repeating cleanse fires at Upkeep (mirrors the DoT-tick loop) — the FIRST debuff (weakened,
	# attached before the cast) should already be gone by the caster's OWN next Upkeep.
	_check(pc.has_effect(&"grand_sacrifice_cleanse"), "dew: the repeating-cleanse marker effect is attached")
	inst._on_phase_changed(PhaseManager.Phase.UPKEEP)
	_check(not pc.has_effect(&"weakened"), "dew: the repeating cleanse removed the debuff on the caster's own next Upkeep")

	await _free_combat(inst)

# --- Misfortune variant: jinxed on every living enemy for 2 turns + an improved cursed for 3 turns ---
func _run_misfortune_variant() -> void:
	var pc: Combatant = _make_summoner(&"misfortune", true)
	var enemy1: Combatant = Combatant.new(); enemy1.base_max_hp = 300; enemy1.apply_stats(); enemy1.start_combat()
	var enemy2: Combatant = Combatant.new(); enemy2.base_max_hp = 300; enemy2.apply_stats(); enemy2.start_combat()
	var inst: Combat = await _build_combat(pc, [], [enemy1, enemy2])

	inst._plan.toggle_ultimate()
	inst._commit_main1()

	for enemy: Combatant in [enemy1, enemy2]:
		_check(enemy.has_effect(&"jinxed"), "misfortune: every living enemy is Jinxed")
		_check(enemy.has_effect(&"cursed"), "misfortune: every living enemy carries the improved Curse")

	await _free_combat(inst)

# --- Hasty variant: 2-turn versions of regen/Empowered/reel_surge, party-wide ---
func _run_hasty_variant() -> void:
	var pc: Combatant = _make_summoner(&"hasty", true)
	var ally: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	ally.begin_turn()
	var enemy: Combatant = Combatant.new(); enemy.base_max_hp = 300; enemy.apply_stats(); enemy.start_combat()
	var inst: Combat = await _build_combat(pc, [ally], [enemy])

	inst._plan.toggle_ultimate()
	inst._commit_main1()

	for c: Combatant in [pc, ally]:
		_check(c.has_effect(&"empowered"), "hasty: party-wide Empowered")
		_check(c.has_effect(&"reel_surge"), "hasty: party-wide reel_surge")
		_check(c._effect_regen_bonus() == Combat.HASTY_REGEN_BONUS, "hasty: party-wide regen bonus (got %d)" % c._effect_regen_bonus())

	await _free_combat(inst)

func _initialize() -> void:
	_run_cannot_stage_without_minion()
	_run_can_stage_with_minion_and_meter()
	_run_firing_consumes_meter_and_minion()
	await _run_ember_variant()
	await _run_dew_variant()
	await _run_misfortune_variant()
	await _run_hasty_variant()

	print(("GRAND SACRIFICE TEST PASSED" if _failures == 0 else "GRAND SACRIFICE TEST FAILED: %d" % _failures))
	quit(_failures)
