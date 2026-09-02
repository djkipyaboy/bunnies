extends SceneTree

# Headless test: Wheat (Hasty) minion rank-2 buff values + stat scaling
# (2026-09-02 harvester-rank2-content spec §2.4).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion_rank2.gd

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
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"HastyRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 1: level 7 (below ability_l4's rank-2 threshold of 8) -> rank-1 values unchanged.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(7)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	inst._turn_manager.combatants.append(minion)

	inst._run_hasty_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and is_equal_approx(haste.magnitude, 20.0), "level 7 stage 1: rank-1 Initiative bonus 20.0 unchanged (got %s)" % [haste.magnitude if haste != null else "null"])

	inst._run_hasty_stage(minion, 2, pc)
	var regen: Effect = pc._find_effect(&"hasty_regen")
	_check(regen != null and regen.regen_bonus == 3, "level 7 stage 2: rank-1 regen bonus 3 unchanged (got %s)" % [regen.regen_bonus if regen != null else "null"])

	inst._run_hasty_stage(minion, 3, pc)
	var empowered: Effect = pc._find_effect(&"empowered")
	_check(empowered != null and empowered.duration == 1, "level 7 stage 3: rank-1 Empowered duration 1 turn unchanged (got %s)" % [empowered.duration if empowered != null else "null"])

	await _cleanup(inst)

## Case 2: level 8+ (ability_l4 rank 2) -> rank-2 values apply (Focus zeroed to isolate rank-up
## from stat scaling, checked separately in case 3).
func _run_rank2_values() -> void:
	var setup: Array = await _build_encounter(8)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	inst._turn_manager.combatants.append(minion)

	inst._run_hasty_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and is_equal_approx(haste.magnitude, 24.0), "level 8 stage 1: rank-2 Initiative bonus 24.0 (got %s)" % [haste.magnitude if haste != null else "null"])

	inst._run_hasty_stage(minion, 2, pc)
	var regen: Effect = pc._find_effect(&"hasty_regen")
	_check(regen != null and regen.regen_bonus == 5, "level 8 stage 2: rank-2 regen bonus 5 (got %s)" % [regen.regen_bonus if regen != null else "null"])

	inst._run_hasty_stage(minion, 3, pc)
	var empowered: Effect = pc._find_effect(&"empowered")
	_check(empowered != null and empowered.duration == 2, "level 8 stage 3: rank-2 Empowered duration 2 turns (got %s)" % [empowered.duration if empowered != null else "null"])

	await _cleanup(inst)

## Case 3: rank-2 regen bonus additionally scales with Focus via ability_magnitude_multiplier();
## Initiative bonus and Empowered duration are NOT magnitude-multiplied (spec §2.4).
func _run_rank2_stat_scaling() -> void:
	var setup: Array = await _build_encounter(8)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.base_stats.focus = 4
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	inst._turn_manager.combatants.append(minion)

	inst._run_hasty_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and is_equal_approx(haste.magnitude, 24.0), "level 8, Focus 4, stage 1: Initiative bonus stays 24.0, not magnitude-multiplied (got %s)" % [haste.magnitude if haste != null else "null"])

	inst._run_hasty_stage(minion, 2, pc)
	var regen: Effect = pc._find_effect(&"hasty_regen")
	var expected: int = ceili(5 * 1.5)
	_check(regen != null and regen.regen_bonus == expected, "level 8, Focus 4, stage 2: regen bonus (5) scaled by 1.5 -> %d (got %s)" % [expected, regen.regen_bonus if regen != null else "null"])

	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	await _run_rank2_stat_scaling()
	print(("HASTY MINION RANK-2 TEST PASSED" if _failures == 0 else "HASTY MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
