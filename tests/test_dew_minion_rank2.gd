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

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	await _run_rank2_stat_scaling()
	print(("DEW MINION RANK-2 TEST PASSED" if _failures == 0 else "DEW MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
