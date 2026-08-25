extends SceneTree

# Headless test for Touch-Me-Not's 3 talent options (2026-08-24 harvester-talent-tree spec §4).
# Calls Combat's private stage functions directly via the same reflection-free approach every other
# minion test uses (they're regular script methods, callable on any Combat instance) — mirrors
# tests/test_hasty_minion.gd's harness for building a real Combat scene, but drives _run_minion_stage
# directly instead of a full spin, since these talents don't touch reel resolution.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_touch_me_not_talents.gd

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
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"tmn_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_overgrown_roots() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_overgrown_roots"), "picks ember_overgrown_roots")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 3, pc)
	var rooted: Effect = enemy._find_effect(&"rooted")
	_check(rooted != null, "ember_overgrown_roots: stage-3 burst applied Rooted to the enemy")
	inst.queue_free()

func _test_no_talent_no_rooted() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	var enemy: Combatant = inst._enemies[0]
	inst._run_minion_stage(minion, 3, pc)
	_check(enemy._find_effect(&"rooted") == null, "no talent: stage-3 burst does NOT apply Rooted")
	inst.queue_free()

func _test_delayed_bloom_echo() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_delayed_bloom"), "picks ember_delayed_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 1, pc)  # stage 1 = 8 base damage, echo = 4
	_check(pc.pending_delayed_bloom_damage == 4, "ember_delayed_bloom: queued a 4-damage echo (50%% of 8) (got %d)" % pc.pending_delayed_bloom_damage)
	inst.queue_free()

func _test_overripe_splashes_overkill() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_overripe"), "picks ember_overripe")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	var victim: Combatant = Combatant.new()
	victim.base_max_hp = 5; victim.apply_stats(); victim.start_combat()
	var bystander: Combatant = Combatant.new()
	bystander.base_max_hp = 50; bystander.apply_stats(); bystander.start_combat()
	inst._enemies = [victim, bystander]
	# _run_minion_stage's damage path reads targets via _enemies_of(), which pulls from
	# _turn_manager.combatants (not _enemies) — both must be kept in sync so the fresh
	# victim/bystander pair (not the real "rat" from setup) are the ones actually hit.
	var combatants: Array[Combatant] = [pc, victim, bystander]
	inst._turn_manager.combatants = combatants
	inst._run_minion_stage(minion, 3, pc)  # stage 3 = 24 damage; victim has 5 HP -> 19 overkill
	_check(not victim.is_alive(), "ember_overripe setup: the low-HP victim died to the stage-3 burst")
	# bystander is also a live enemy of the same AoE burst, so it eats the base 24 dmg from the
	# main loop PLUS the 19 overkill splash -> 43 total (not just the 19 splash in isolation).
	_check(bystander.hp == bystander.max_hp - 43, "ember_overripe: overkill splashed onto the bystander on top of its own base hit (got %d/%d)" % [bystander.hp, bystander.max_hp])
	inst.queue_free()

func _initialize() -> void:
	await _test_overgrown_roots()
	await _test_no_talent_no_rooted()
	await _test_delayed_bloom_echo()
	await _test_overripe_splashes_overkill()
	quit(_failures)
