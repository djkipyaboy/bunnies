extends SceneTree

# Headless test: Touch-Me-Not (Ember) minion rank-2 stage damage + stat scaling
# (2026-09-02 harvester-rank2-content spec §2.1). Verifies rank-1 values are unchanged
# (regression) and rank-2 values + ability_magnitude_multiplier() apply once level >= 5
# (base_ability's rank-2 threshold, per ability_talent_row_unlock_level()).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ember_minion_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a real Combat instance via CombatHandoff (mirrors every existing minion test file's
## harness, e.g. tests/test_dew_minion.gd's _new_summoner_encounter) with a Summoner PC at
## [param level] and one rat enemy. Returns [inst, pc, enemy]. Doesn't drive to any particular
## turn/spin window — direct stage-function calls below don't need one.
func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"EmberRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
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

## Case 1: level 4 (below base_ability's rank-2 threshold of 5) -> rank-1 stage damage unchanged.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(4)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	inst._turn_manager.combatants.append(minion)

	for stage: int in [1, 2, 3]:
		var hp_before: int = enemy.hp
		inst._run_ember_stage(minion, stage, pc)
		var expected: int = Combat.MINION_BASE_STAGE_DAMAGE * stage
		_check(enemy.hp == hp_before - expected, "level 4 stage %d: rank-1 damage %d unchanged (hp %d -> %d)" % [stage, expected, hp_before, enemy.hp])

	await _cleanup(inst)

## Case 2: level 5+ (base_ability rank 2) -> rank-2 per-stage constants apply. Focus zeroed so this
## case isolates rank-up from stat scaling (checked separately in case 3).
func _run_rank2_values() -> void:
	var setup: Array = await _build_encounter(5)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.base_stats.focus = 0
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	inst._turn_manager.combatants.append(minion)

	var expected_rank2: Array[int] = [12, 22, 32]
	for i: int in range(3):
		var stage: int = i + 1
		var hp_before: int = enemy.hp
		inst._run_ember_stage(minion, stage, pc)
		_check(enemy.hp == hp_before - expected_rank2[i], "level 5 stage %d: rank-2 damage %d applied (hp %d -> %d)" % [stage, expected_rank2[i], hp_before, enemy.hp])

	await _cleanup(inst)

## Case 3: rank-2 damage additionally scales with Focus via ability_magnitude_multiplier() —
## Focus 4 -> StatScaling.multiplier(4) == 1.5 (matches tests/test_stat_scaling.gd's own fixture).
func _run_rank2_stat_scaling() -> void:
	var setup: Array = await _build_encounter(5)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.base_stats.focus = 4
	_check(is_equal_approx(pc.ability_magnitude_multiplier(), 1.5), "sanity: Focus 4 -> ability_magnitude_multiplier() 1.5 (got %f)" % pc.ability_magnitude_multiplier())
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	inst._turn_manager.combatants.append(minion)

	var hp_before: int = enemy.hp
	inst._run_ember_stage(minion, 1, pc)
	var expected: int = ceili(12 * 1.5)
	_check(enemy.hp == hp_before - expected, "level 5, Focus 4, stage 1: rank-2 damage (12) scaled by 1.5 -> %d (hp %d -> %d)" % [expected, hp_before, enemy.hp])

	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	await _run_rank2_stat_scaling()
	print(("EMBER MINION RANK-2 TEST PASSED" if _failures == 0 else "EMBER MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
