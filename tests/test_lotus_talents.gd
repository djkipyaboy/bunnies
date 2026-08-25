extends SceneTree

# Headless test for Lotus's 3 talent options (2026-08-24 harvester-talent-tree spec §5). Drives
# _run_minion_stage/_run_dew_stage directly, same approach as test_touch_me_not_talents.gd.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lotus_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"lotus_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_evergreen_bloom_prevents_expiry_and_loops() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l2", &"dew_evergreen_bloom"), "picks dew_evergreen_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	minion.minion_caster = pc
	pc.active_minion = minion
	inst._run_minion_stage(minion, 3, pc)
	_check(minion.is_alive(), "dew_evergreen_bloom: minion survives past stage 3")
	pc.hp = 10
	inst._run_minion_stage(minion, 4, pc)
	_check(pc.hp > 10, "dew_evergreen_bloom: stage 4+ still heals (the looping reduced heal)")
	inst.queue_free()

func _test_twin_petal_cleanses_two() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l2", &"dew_twin_petal"), "picks dew_twin_petal")
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	minion.minion_caster = pc
	var w1: Effect = EffectLibrary.make(&"weakened"); w1.id = &"weakened"
	pc.attach_effect(w1)
	var s1: Effect = EffectLibrary.make(&"sundered"); s1.id = &"sundered"
	pc.attach_effect(s1)
	inst._run_minion_stage(minion, 2, pc)
	_check(pc._find_effect(&"weakened") == null and pc._find_effect(&"sundered") == null, "dew_twin_petal: both debuffs cleansed by one stage-2 tick")
	inst.queue_free()

func _test_guardian_bloom_adds_shield() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l2", &"dew_guardian_bloom"), "picks dew_guardian_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"dew")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 3, pc)
	_check(pc.shield_hp > 0, "dew_guardian_bloom: stage 3 grants a flat shield (got %d)" % pc.shield_hp)
	inst.queue_free()

func _initialize() -> void:
	await _test_evergreen_bloom_prevents_expiry_and_loops()
	await _test_twin_petal_cleanses_two()
	await _test_guardian_bloom_adds_shield()
	quit(_failures)
