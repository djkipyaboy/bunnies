extends SceneTree

# Headless test for Strawfellow's Due's 3 Ultimate-row talent options (2026-08-24
# harvester-talent-tree spec §9). Calls _apply_grand_sacrifice() directly with a pre-summoned
# minion of the relevant variant, mirroring tests/test_grand_sacrifice.gd's own direct-call harness.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_strawfellow_due_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	# 2026-08-24 adaptation: on this machine the CombatHandoff autoload is sometimes not yet
	# attached under root at the very first _init() tick (observed to depend on unrelated script
	# parse/compile timing, not on anything in this file) — wait for it defensively instead of
	# assuming it's already there, matching tests/test_nightshade_talents.gd's harness.
	var CombatHandoff: Node = get_root().get_node_or_null("CombatHandoff")
	while CombatHandoff == null:
		await process_frame
		CombatHandoff = get_root().get_node_or_null("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"strawfellow_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_petrifying_burst_forces_stun() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_petrifying_burst"), "picks strawfellow_petrifying_burst")
	inst._defender = inst._enemies[0]
	inst._apply_grand_sacrifice(pc, &"ember")
	_check(inst._enemies[0].force_stun_next_turn, "strawfellow_petrifying_burst: primary target's force_stun_next_turn is set")
	inst.queue_free()

func _test_undying_bloom_cleanses_whole_party() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_undying_bloom"), "picks strawfellow_undying_bloom")
	var weakened: Effect = EffectLibrary.make(&"weakened")
	pc.attach_effect(weakened)
	inst._apply_grand_sacrifice(pc, &"dew")
	_check(pc._find_effect(&"weakened") == null, "strawfellow_undying_bloom: immediately cleansed the caster's debuff")
	inst.queue_free()

func _test_withering_doom_doubles_damage_vs_debuffed() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_withering_doom"), "picks strawfellow_withering_doom")
	var enemy: Combatant = inst._enemies[0]
	enemy.attach_effect(EffectLibrary.make(&"weakened"))
	inst._apply_grand_sacrifice(pc, &"misfortune")
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 30.0), "strawfellow_withering_doom: doubled Curse's dot_base_damage vs. a Weakened target (got %.1f)" % (curse.dot_base_damage if curse != null else -1.0))
	inst.queue_free()

func _test_withering_doom_no_bonus_without_debuff() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ultimate", &"strawfellow_withering_doom"), "picks strawfellow_withering_doom")
	var enemy: Combatant = inst._enemies[0]
	inst._apply_grand_sacrifice(pc, &"misfortune")
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and is_equal_approx(curse.dot_base_damage, 15.0), "strawfellow_withering_doom: NO bonus vs. an undebuffed target (got %.1f)" % (curse.dot_base_damage if curse != null else -1.0))
	inst.queue_free()

func _init() -> void:
	await _test_petrifying_burst_forces_stun()
	await _test_undying_bloom_cleanses_whole_party()
	await _test_withering_doom_doubles_damage_vs_debuffed()
	await _test_withering_doom_no_bonus_without_debuff()
	quit(_failures)
