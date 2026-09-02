extends SceneTree

# Headless test: Nightshade (Misfortune) minion rank-2 curse damage + the Mutual Exhaustion talent
# (2026-09-02 harvester-rank2-content spec §2.3).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_encounter(level: int) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = level
	pc.base_stats.focus = 0
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"MisfortuneRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
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

## Case 1: level 6 (below ability_l3's rank-2 threshold of 7) -> rank-1 curse (12.0) unchanged,
## and stage 3 does NOT reapply Weakened/Sundered without the (now-removed) Creeping Blight talent.
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(6)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	inst._turn_manager.combatants.append(minion)

	inst._run_misfortune_stage(minion, 1, pc)
	inst._run_misfortune_stage(minion, 2, pc)
	enemy.remove_effect(&"weakened")
	enemy.remove_effect(&"sundered")
	inst._run_misfortune_stage(minion, 3, pc)

	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 12.0), "level 6: rank-1 curse dot_base_damage 12.0 unchanged (got %s)" % [curse.dot_base_damage if curse != null else "null"])
	_check(not enemy.has_effect(&"weakened"), "level 6: stage 3 does not reapply Weakened (no talent picked)")

	await _cleanup(inst)

## Case 2: level 7+ (ability_l3 rank 2), no Mutual Exhaustion talent -> curse bumps to 18.0 AND
## stage 3's now-unconditional baseline reapplies Weakened + Sundered.
func _run_rank2_baseline() -> void:
	var setup: Array = await _build_encounter(7)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	inst._turn_manager.combatants.append(minion)

	inst._run_misfortune_stage(minion, 1, pc)
	inst._run_misfortune_stage(minion, 2, pc)
	enemy.remove_effect(&"weakened")
	enemy.remove_effect(&"sundered")
	inst._run_misfortune_stage(minion, 3, pc)

	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 18.0), "level 7: rank-2 curse dot_base_damage 18.0 (got %s)" % [curse.dot_base_damage if curse != null else "null"])
	_check(enemy.has_effect(&"weakened") and enemy.has_effect(&"sundered"), "level 7: rank-2 baseline reapplies Weakened + Sundered at stage 3 without the talent")
	_check(not enemy.has_effect(&"exhausted_weakened"), "level 7: no Mutual Exhaustion talent picked -> no Exhausted merge")

	await _cleanup(inst)

## Case 3: level 7+, Mutual Exhaustion picked, target already Weakened + Sundered from stage 2 ->
## stage 3 merges them into Exhausted (+ Slow) instead of a plain reapply.
func _run_mutual_exhaustion_merge() -> void:
	var setup: Array = await _build_encounter(7)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	pc.ability_talent_picks[&"ability_l3"] = &"misfortune_mutual_exhaustion"
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	inst._turn_manager.combatants.append(minion)

	inst._run_misfortune_stage(minion, 1, pc)
	inst._run_misfortune_stage(minion, 2, pc)
	_check(enemy.has_effect(&"weakened") and enemy.has_effect(&"sundered"), "setup: enemy carries both Weakened and Sundered after stage 2")
	inst._run_misfortune_stage(minion, 3, pc)

	_check(not enemy.has_effect(&"weakened"), "merge: plain Weakened was removed")
	_check(not enemy.has_effect(&"sundered"), "merge: plain Sundered was removed")
	_check(enemy.has_effect(&"exhausted_weakened"), "merge: Exhausted's outgoing half is active")
	_check(enemy.has_effect(&"exhausted_sundered"), "merge: Exhausted's incoming half is active")
	_check(enemy.has_effect(&"slow"), "merge: Slow was bundled in")

	# Stacking: a LATER plain Weakened application must multiply on top of Exhausted, not no-op.
	var mult_before: float = enemy.outgoing_damage_multiplier()
	enemy.attach_effect(EffectLibrary.make(&"weakened"))
	var mult_after: float = enemy.outgoing_damage_multiplier()
	_check(mult_after < mult_before, "stacking: a later plain Weakened multiplies further on top of Exhausted's outgoing reduction (%f -> %f)" % [mult_before, mult_after])

	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_baseline()
	await _run_mutual_exhaustion_merge()
	print(("MISFORTUNE MINION RANK-2 TEST PASSED" if _failures == 0 else "MISFORTUNE MINION RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
