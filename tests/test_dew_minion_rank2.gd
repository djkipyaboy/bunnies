extends SceneTree

# Headless test: Lotus (Dew) minion rank-2 heal values + stat scaling
# (2026-09-02 harvester-rank2-content spec §2.2).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"DewRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	var enemy: Combatant = inst._enemies[0]
	return [inst, pc, enemy]

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 1: level 5 (below ability_l2's rank-2 threshold of 6) -> rank-1 heals unchanged.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(5)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	inst._turn_manager.combatants.append(minion)

	var expected_rank1: Array[int] = [8, 12, 16]
	for i: int in range(3):
		var stage: int = i + 1
		pc.take_damage(30)
		var hp_before: int = pc.hp
		inst._run_dew_stage(minion, stage, pc)
		_check(pc.hp == mini(hp_before + expected_rank1[i], pc.max_hp), "level 5 stage %d: rank-1 heal %d unchanged (hp %d -> %d)" % [stage, expected_rank1[i], hp_before, pc.hp])

	await _cleanup(inst)

## Case 2: level 6+ (ability_l2 rank 2) -> rank-2 per-stage heals apply (Focus zeroed to isolate
## rank-up from stat scaling, checked separately in case 3).
func _run_rank2_values() -> void:
	var setup: Array = await _build_encounter(6)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	inst._turn_manager.combatants.append(minion)

	var expected_rank2: Array[int] = [12, 18, 24]
	for i: int in range(3):
		var stage: int = i + 1
		pc.take_damage(30)
		var hp_before: int = pc.hp
		inst._run_dew_stage(minion, stage, pc)
		_check(pc.hp == mini(hp_before + expected_rank2[i], pc.max_hp), "level 6 stage %d: rank-2 heal %d applied (hp %d -> %d)" % [stage, expected_rank2[i], hp_before, pc.hp])

	await _cleanup(inst)

## Case 3: rank-2 heal additionally scales with Focus via ability_magnitude_multiplier().
func _run_rank2_stat_scaling() -> void:
	var setup: Array = await _build_encounter(6)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 4
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	inst._turn_manager.combatants.append(minion)

	pc.take_damage(30)
	var hp_before: int = pc.hp
	inst._run_dew_stage(minion, 1, pc)
	var expected: int = ceili(12 * 1.5)
	_check(pc.hp == mini(hp_before + expected, pc.max_hp), "level 6, Focus 4, stage 1: rank-2 heal (12) scaled by 1.5 -> %d (hp %d -> %d)" % [expected, hp_before, pc.hp])

	await _cleanup(inst)

## Case 4 (2026-09-02 C1 fix regression): the 3 cases above all call inst._run_dew_stage(minion,
## stage, pc) directly with an EXPLICIT caster — none of them exercise the real,
## caster-OMITTED path _take_minion_turn() actually uses for a minion's stage-2/3 turns
## (combat.gd's _take_minion_turn() calls _run_minion_stage(c, c.minion_stage) with NO caster
## argument). Drives a REAL minion turn end-to-end (real spin, real turn-order advance to the
## minion's own turn) with caster never explicitly passed anywhere in this test, and asserts the
## rank-2 heal value (not rank-1's) came through anyway — proving the _run_dew_stage() owner
## fallback (`caster if caster != null else minion.minion_caster`) is what's actually firing.
## Mirrors tests/test_dew_minion.gd's _new_summoner_encounter/_stage_and_force_dew/_pump_one_frame
## harness.
func _run_real_minion_turn_owner_resolution() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.base_stats.focus = 0
	pc.level = 6  # Dew's rank-2 (ability_l2) threshold
	pc.weapon.base_damage = 0.0  # isolate the minion's own heals — no weapon-attack noise
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 999
	pc.attach_effect(taunt)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"DewRank2OwnerResolution", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	var enemy: Combatant = inst._enemies[0]
	if enemy.weapon != null:
		enemy.weapon.base_damage = 0.0

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "owner-resolution setup: reached the Summoner's pre-spin window")

	inst._plan.toggle_extra_ability(&"dew_minion")
	inst._commit_main1()
	_check(pc.summon_reel != null, "owner-resolution setup: commit appended a real summon_reel")
	var forced_face: ReelFace = null
	for f: ReelFace in pc.summon_reel.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			forced_face = f
			break
	_check(forced_face != null, "owner-resolution setup: found a SUCCESS face to force")
	pc.summon_reel.faces = [forced_face]
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()
	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame

	var minion: Combatant = pc.active_minion
	_check(minion != null and minion.is_alive() and minion.minion_stage == 1, "owner-resolution setup: Dew Minion summoned, stage 1 fired")

	# End the Summoner's turn and drive real frames until the minion's own turn fires stage 2 — this
	# is _take_minion_turn()'s real path, which calls _run_minion_stage(c, c.minion_stage) with NO
	# caster argument. caster is never explicitly passed anywhere below.
	pc.take_damage(50)
	var hp_before: int = pc.hp
	inst._on_end_turn_pressed()
	var stage2_guard: int = 0
	while minion.minion_stage < 2 and stage2_guard < 3000:
		stage2_guard += 1
		if inst._awaiting_player_spin and inst._attacker == pc:
			inst._on_spin_pressed()
		elif inst._awaiting_end_turn and inst._attacker == pc:
			inst._on_end_turn_pressed()
		await process_frame
	_check(minion.minion_stage == 2, "owner-resolution: minion reached stage 2 via its own real turn (got %d)" % minion.minion_stage)
	_check(pc.hp == mini(hp_before + Combat.DEW_STAGE2_HEAL_RANK2, pc.max_hp), "owner-resolution: stage-2 heal came through as the RANK-2 value (%d), not rank-1's 12, even though caster was never explicitly passed (hp %d -> %d)" % [Combat.DEW_STAGE2_HEAL_RANK2, hp_before, pc.hp])

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	await _run_rank2_stat_scaling()
	await _run_real_minion_turn_owner_resolution()
	print(("DEW MINION RANK-2 TEST PASSED" if _failures == 0 else "DEW MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
