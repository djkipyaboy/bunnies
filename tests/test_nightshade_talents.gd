extends SceneTree

# Headless test for Nightshade's 3 talent options + the Harvest's Favor Ill Fortune synergy
# (2026-08-24 harvester-talent-tree spec §6, §1).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_nightshade_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	# 2026-08-24 adaptation: on this machine the CombatHandoff autoload is sometimes not yet
	# attached under root at the very first _init() tick (observed to depend on unrelated script
	# parse/compile timing, not on anything in this file) — wait for it defensively instead of
	# assuming it's already there, matching the intent of test_touch_me_not_talents.gd's harness.
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
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"nightshade_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_withering_touch_reduces_healing() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_withering_touch"), "picks misfortune_withering_touch")
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	enemy.hp = 1
	inst._run_minion_stage(minion, 3, pc)
	var curse: Effect = enemy._find_effect(&"cursed")
	_check(curse != null and curse.heal_multiplier < 1.0, "misfortune_withering_touch: Cursed carries a heal_multiplier below 1.0 (got %.2f)" % (curse.heal_multiplier if curse != null else -1.0))
	var before: int = enemy.hp
	enemy.heal(20)
	_check(enemy.hp < before + 20, "misfortune_withering_touch: heal() actually respects heal_multiplier (healed to %d, expected less than %d)" % [enemy.hp, before + 20])
	inst.queue_free()

func _test_creeping_blight_reapplies_debuffs() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_creeping_blight"), "picks misfortune_creeping_blight")
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 3, pc)
	_check(enemy._find_effect(&"weakened") != null, "misfortune_creeping_blight: stage 3 also applies Weakened")
	_check(enemy._find_effect(&"sundered") != null, "misfortune_creeping_blight: stage 3 also applies Sundered")
	_check(enemy._find_effect(&"cursed") != null, "misfortune_creeping_blight: stage 3 still applies Cursed")
	inst.queue_free()

func _test_ill_fortune_applies_jinxed_at_stage2() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_ill_fortune"), "picks misfortune_ill_fortune")
	var minion: Combatant = MinionLibrary.make(false, &"misfortune")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 2, pc)
	_check(enemy._find_effect(&"jinxed") != null, "misfortune_ill_fortune: stage 2 also applies Jinxed")
	inst.queue_free()

func _test_harvest_favor_ill_fortune_synergy() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l3", &"misfortune_ill_fortune"), "picks misfortune_ill_fortune")
	pc.active_minion = MinionLibrary.make(false, &"misfortune")
	var target: Combatant = inst._enemies[0]
	var weakened: Effect = EffectLibrary.make(&"weakened")
	target.attach_effect(weakened)
	pc.harvest_favor_on_hit(target, [pc])
	_check(target._find_effect(&"jinxed") != null, "harvest_favor + Ill Fortune: Nightshade branch also applies Jinxed on top of the duration extension")
	inst.queue_free()

func _test_heal_rounds_up_not_to_nearest() -> void:
	# Direct unit-level check of Combatant.heal()'s rounding convention, independent of any real
	# combat/ability wiring. 0.5 is a tie either way (roundf and ceili agree), which is why the
	# task-6 review flagged that the existing suite couldn't distinguish the two functions — a
	# non-tie-breaking multiplier is needed to actually pin the ceili() convention down. amount=15,
	# mult=0.75 -> 11.25: roundf would give 11 (regression), ceili must give 12.
	var c: Combatant = Combatant.new()
	c.max_hp = 100
	c.hp = 50
	var e: Effect = Effect.new()
	e.heal_multiplier = 0.75
	c.active_effects.append(e)
	c.heal(15)
	_check(c.hp == 62, "heal() rounds UP (ceili), not to-nearest: amount=15, mult=0.75 -> expected hp 62, got %d" % c.hp)

func _init() -> void:
	await _test_withering_touch_reduces_healing()
	await _test_creeping_blight_reapplies_debuffs()
	await _test_ill_fortune_applies_jinxed_at_stage2()
	await _test_harvest_favor_ill_fortune_synergy()
	_test_heal_rounds_up_not_to_nearest()
	quit(_failures)
