extends SceneTree

# Headless end-to-end test for Warrior Sundering Strike's 2 on-hit talents — Twist the Knife
# (bonus damage vs. an already-Bled target) and Vicious Return (full Stamina refund vs. an
# already-Sundered target). Both live in combat.gd's _apply_attack() (orchestrator-level, reads
# live per-hit Combatant state), so — unlike this ability's pickability/shape, already covered in
# tests/test_ability_talents_warrior.gd — they require a running Combat scene to prove for real.
#
# Adapts tests/test_wheat_talents.gd's _new_combat_with_harvester() pattern (a real combat.tscn
# instance built via CombatHandoff.begin_encounter()) for a Warrior instead of a Harvester, and
# reuses test_reel_surge_buff.gd's _force_all_success()/_do_spin() drive-a-real-spin technique so
# the outcome is deterministic instead of random.
#
# Run:
# ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_sundering_strike_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a fresh CombatHandoff-driven combat.tscn instance with a level-10 Warrior PC (3-reel
## Slashing weapon baseline, start_stamina 3 == Sundering Strike's exact cost) and one rat enemy
## (its own weapon zeroed out so retaliation never muddies the damage/stamina numbers this test
## reads), rolls initiative, and drives frames until it's the Warrior's own pre-spin window.
## Returns [inst, pc, enemy]. (Mirrors test_wheat_talents.gd's _new_combat_with_harvester() and
## test_reel_surge_buff.gd's _new_skirmisher_encounter(), just a different class.)
func _new_warrior_combat(encounter_id: StringName) -> Array:
	var CombatHandoff: Node = get_root().get_node_or_null("CombatHandoff")
	while CombatHandoff == null:
		await process_frame
		CombatHandoff = get_root().get_node_or_null("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.level = Combatant.MAX_LEVEL  # unlocks every talent row (ability_l2 included)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, encounter_id, "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()

	var enemy: Combatant = inst._enemies[0]
	enemy.weapon.base_damage = 0.0  # isolate the Warrior's own attack — no retaliation noise

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "[%s] reached the Warrior's pre-spin window" % encounter_id)

	return [inst, pc, enemy]

## Forces every reel in [param reels] to a single SUCCESS-tier face (mirrors
## test_reel_surge_buff.gd's helper), so a real spin's outcome is deterministic instead of random.
func _force_all_success(reels: Array[ActionReel]) -> void:
	for reel: ActionReel in reels:
		var forced: ReelFace = null
		for f: ReelFace in reel.faces:
			if f.result_tier == ReelFace.ResultTier.SUCCESS:
				forced = f
				break
		if forced != null:
			reel.faces = [forced]

## Stages Sundering Strike, commits it, forces every reel (weapon baseline + the Sundering Strike
## reel) to a guaranteed hit, then drives a real spin to settle. Returns nothing — callers read
## whatever pre/post state they need off [param pc]/[param enemy] themselves.
func _stage_and_resolve_sundering_strike(inst: Combat, pc: Combatant) -> void:
	inst._plan.toggle_extra_ability(&"sundering_strike")
	_check(inst._plan.staged_extra_ability_id == &"sundering_strike", "sundering_strike staged via the real toggle")
	inst._commit_main1()
	_force_all_success(pc.turn_reels)
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()
	var guard: int = 0
	while inst._pending_strips > 0 and guard < 2000:
		guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the forced spin's strips settled without hanging")

func _cleanup(inst: Combat) -> void:
	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Twist the Knife (Finding 3): Sundering Strike deals +20% bonus damage if the target already
## carries Bleed BEFORE the hit. Two full separate encounters (Bled vs. plain), otherwise
## identical — Bleed itself is a DAMAGE_OVER_TIME effect (see combat/effect_library.gd), not a
## MULTIPLIER_EDIT, so it doesn't skew the base hit's own damage; any difference between the two
## runs is Twist the Knife's own bonus.
func _test_twist_the_knife_bonus_damage() -> void:
	var setup_bled: Array = await _new_warrior_combat(&"TwistKnifeBled")
	var inst_bled: Combat = setup_bled[0]
	var pc_bled: Combatant = setup_bled[1]
	var enemy_bled: Combatant = setup_bled[2]
	_check(pc_bled.pick_ability_talent(&"ability_l2", &"sunder_twist_knife"), "picks sunder_twist_knife")
	enemy_bled.attach_effect(EffectLibrary.make(&"bleed"))
	var hp_before_bled: int = enemy_bled.hp
	await _stage_and_resolve_sundering_strike(inst_bled, pc_bled)
	var dmg_bled: int = hp_before_bled - enemy_bled.hp
	await _cleanup(inst_bled)

	var setup_plain: Array = await _new_warrior_combat(&"TwistKnifePlain")
	var inst_plain: Combat = setup_plain[0]
	var pc_plain: Combatant = setup_plain[1]
	var enemy_plain: Combatant = setup_plain[2]
	_check(pc_plain.pick_ability_talent(&"ability_l2", &"sunder_twist_knife"), "picks sunder_twist_knife (plain-target run)")
	var hp_before_plain: int = enemy_plain.hp
	await _stage_and_resolve_sundering_strike(inst_plain, pc_plain)
	var dmg_plain: int = hp_before_plain - enemy_plain.hp
	await _cleanup(inst_plain)

	_check(dmg_bled > dmg_plain, "sunder_twist_knife: Sundering Strike deals MORE damage vs. a Bled target (%d) than vs. a plain target (%d)" % [dmg_bled, dmg_plain])

## Vicious Return (Finding 3): Sundering Strike refunds its full Stamina cost if it hits a target
## that's already Sundered BEFORE the hit. Records Stamina before casting, after the cast-time
## spend, and after the hit resolves — the refund landing means the post-resolve value equals the
## pre-cast value (net-zero cost), NOT just higher than the post-spend value.
func _test_vicious_return_refunds_stamina() -> void:
	var setup: Array = await _new_warrior_combat(&"ViciousReturn")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	_check(pc.pick_ability_talent(&"ability_l2", &"sunder_vicious_return"), "picks sunder_vicious_return")
	enemy.attach_effect(EffectLibrary.make(&"sundered"))

	var stamina_before_cast: int = pc.resource_pool.stamina
	inst._plan.toggle_extra_ability(&"sundering_strike")
	inst._commit_main1()  # spends the ability's Stamina cost
	var stamina_after_cast: int = pc.resource_pool.stamina
	_check(stamina_after_cast < stamina_before_cast, "sanity: casting Sundering Strike actually spent Stamina (%d -> %d)" % [stamina_before_cast, stamina_after_cast])

	_force_all_success(pc.turn_reels)
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()
	var guard: int = 0
	while inst._pending_strips > 0 and guard < 2000:
		guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the forced spin's strips settled without hanging")

	_check(pc.resource_pool.stamina == stamina_before_cast, "sunder_vicious_return: Stamina after the full turn resolves equals pre-cast Stamina (net-zero cost, got %d, want %d)" % [pc.resource_pool.stamina, stamina_before_cast])
	await _cleanup(inst)

func _initialize() -> void:
	await _test_twist_the_knife_bonus_damage()
	await _test_vicious_return_refunds_stamina()

	print(("SUNDERING STRIKE TALENTS TEST PASSED" if _failures == 0 else "SUNDERING STRIKE TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
