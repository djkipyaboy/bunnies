extends SceneTree

# Headless test: Grand Sacrifice / Strawfellow's Due rank-2 at level 10
# (2026-09-02 harvester-rank2-content spec §4).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_grand_sacrifice_rank2.gd

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
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"GrandSacrificeRank2Test", "res://world/overworld_demo.tscn", Vector2.ZERO)
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

## Case 1: level 9 (below ultimate's rank-2 threshold of 10) -> rank-1 values unchanged (Ember
## variant checked as the representative case for the flat-burst shape; Dew/Misfortune/Hasty
## follow the identical rank-lookup pattern, covered by case 2's rank-2 checks below).
func _run_rank1_regression() -> void:
	var setup: Array = await _build_encounter(9)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	inst._defender = enemy
	var hp_before: int = enemy.hp
	inst._apply_grand_sacrifice(pc, &"ember")
	_check(enemy.hp == hp_before - 40, "level 9: rank-1 Ember burst 40 unchanged (hp %d -> %d)" % [hp_before, enemy.hp])

	await _cleanup(inst)

## Case 2: level 10 (ultimate rank 2) -> rank-2 values apply across all four variants.
func _run_rank2_values() -> void:
	# Ember burst.
	var setup: Array = await _build_encounter(10)
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	inst._defender = enemy
	var hp_before: int = enemy.hp
	inst._apply_grand_sacrifice(pc, &"ember")
	_check(enemy.hp == hp_before - 60, "level 10: rank-2 Ember burst 60 (hp %d -> %d)" % [hp_before, enemy.hp])
	await _cleanup(inst)

	# Dew heal + Thorns + duration.
	setup = await _build_encounter(10)
	inst = setup[0]
	pc = setup[1]
	pc.take_damage(50)
	var hp_before_heal: int = pc.hp
	inst._apply_grand_sacrifice(pc, &"dew")
	_check(pc.hp == mini(hp_before_heal + 45, pc.max_hp), "level 10: rank-2 Dew heal 45 (hp %d -> %d)" % [hp_before_heal, pc.hp])
	var thorns: Effect = pc._find_effect(&"grand_sacrifice_thorns")
	_check(thorns != null and is_equal_approx(thorns.thorns_pct, 0.45), "level 10: rank-2 Dew Thorns 45%% (got %s)" % [thorns.thorns_pct if thorns != null else "null"])
	_check(thorns != null and thorns.duration == 4, "level 10: rank-2 Dew Thorns duration 3 turns + caster's own +1 = 4 (got %s)" % [thorns.duration if thorns != null else "null"])
	await _cleanup(inst)

	# Misfortune curse damage + durations.
	setup = await _build_encounter(10)
	inst = setup[0]
	pc = setup[1]
	enemy = setup[2]
	inst._apply_grand_sacrifice(pc, &"misfortune")
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 22.0), "level 10: rank-2 Misfortune curse dot_base_damage 22.0 (got %s)" % [curse.dot_base_damage if curse != null else "null"])
	_check(curse != null and curse.duration == 4, "level 10: rank-2 Misfortune curse duration 4 turns (got %s)" % [curse.duration if curse != null else "null"])
	var jinx: Effect = enemy._find_effect(&"jinxed")
	_check(jinx != null and jinx.duration == 3, "level 10: rank-2 Misfortune Jinxed duration 3 turns (got %s)" % [jinx.duration if jinx != null else "null"])
	await _cleanup(inst)

	# Hasty regen/Empowered/surge duration.
	setup = await _build_encounter(10)
	inst = setup[0]
	pc = setup[1]
	inst._apply_grand_sacrifice(pc, &"hasty")
	var regen: Effect = pc._find_effect(&"grand_sacrifice_regen")
	_check(regen != null and regen.regen_bonus == 5, "level 10: rank-2 Hasty regen bonus 5 (rank-2 HASTY_REGEN_BONUS, got %s)" % [regen.regen_bonus if regen != null else "null"])
	_check(regen != null and regen.duration == 4, "level 10: rank-2 Hasty duration 3 turns + caster's own +1 = 4 (got %s)" % [regen.duration if regen != null else "null"])
	await _cleanup(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_values()
	print(("GRAND SACRIFICE RANK-2 TEST PASSED" if _failures == 0 else "GRAND SACRIFICE RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
