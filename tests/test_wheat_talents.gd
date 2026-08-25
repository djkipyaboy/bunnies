extends SceneTree

# Headless test for Wheat's 3 talent options (2026-08-24 harvester-talent-tree spec §7).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_wheat_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _new_combat_with_harvester() -> Array:
	# 2026-08-24 adaptation (matches test_nightshade_talents.gd): on this machine the CombatHandoff
	# autoload is sometimes not yet attached under root at the very first _init() tick — wait for
	# it defensively instead of assuming it's already there.
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
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"wheat_talents", "res://world/overworld_demo.tscn", Vector2.ZERO)
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()
	return [inst, pc]

func _test_bountiful_harvest_refunds_next_cast() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l4", &"hasty_bountiful_harvest"), "picks hasty_bountiful_harvest")
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 2, pc)
	_check(pc.resource_pool.pending_ability_refund > 0, "hasty_bountiful_harvest: stage 2 queued a refund (got %d)" % pc.resource_pool.pending_ability_refund)
	var before: int = pc.resource_pool.mana
	pc.resource_pool.spend({&"mana": 4})
	_check(pc.resource_pool.mana > before - 4, "hasty_bountiful_harvest: next ability's spend was partially refunded (mana %d, spent from %d)" % [pc.resource_pool.mana, before])
	_check(pc.resource_pool.pending_ability_refund == 0, "hasty_bountiful_harvest: refund is consumed after one ability")
	inst.queue_free()

func _test_unshakeable_roots_grants_immunity() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l4", &"hasty_unshakeable_roots"), "picks hasty_unshakeable_roots")
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 1, pc)
	var haste: Effect = pc._find_effect(&"hasty_initiative")
	_check(haste != null and &"rooted" in haste.immune_effect_ids, "hasty_unshakeable_roots: stage-1 Initiative buff grants Rooted immunity")
	inst.queue_free()

func _test_charged_growth_marks_surge_reel() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"ability_l4", &"hasty_charged_growth"), "picks hasty_charged_growth")
	var minion: Combatant = MinionLibrary.make(false, &"hasty")
	minion.minion_caster = pc
	inst._run_minion_stage(minion, 3, pc)  # attaches reel_surge
	# _commit_main1() operates on the orchestrator's _attacker, which is whoever's turn it currently
	# is (initiative is rolled randomly, so it isn't always pc immediately) — wait for pc's own
	# pre-spin window first, matching test_reel_surge_buff.gd's _new_skirmisher_encounter guard.
	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "charged_growth setup: reached pc's pre-spin window")
	pc.turn_reels = [ActionReel.make_default(pc.weapon_type()), ActionReel.make_default(pc.weapon_type())]
	inst._commit_main1()
	_check(pc.charged_growth_reel_index == pc.turn_reels.size() - 1, "hasty_charged_growth: the surge-appended reel's index was recorded (got %d, expected %d)" % [pc.charged_growth_reel_index, pc.turn_reels.size() - 1])
	inst.queue_free()

func _init() -> void:
	await _test_bountiful_harvest_refunds_next_cast()
	await _test_unshakeable_roots_grants_immunity()
	await _test_charged_growth_marks_surge_reel()
	quit(_failures)
