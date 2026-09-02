extends SceneTree

# Headless end-to-end test for Misfortune Minion (2026-08-16 summoner-ability-kit spec §2).
# Mirrors tests/test_dew_minion.gd's exact CombatHandoff/force-a-reel-tier/frame-polling harness,
# adapted for Misfortune Minion being staged as an EXTRA ability (toggle_extra_ability()) that
# debuffs every ENEMY (not heals allies) across its 3 stages.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_misfortune_minion.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a fresh CombatHandoff-driven combat.tscn instance with a Summoner PC (weapon damage
## zeroed) and one rat enemy, rolls initiative, and drives frames until it's the Summoner's own
## pre-spin window. Returns [inst, pc, enemy]. (Mirrors test_dew_minion.gd's
## _new_summoner_encounter exactly.)
func _new_summoner_encounter(encounter_id: StringName) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	# 2026-09-02 harvester-rank2-content C1 fix: real stage-2/3 minion turns now correctly resolve
	# rank/stat-scaling from minion.minion_caster (this pc) instead of always defaulting to
	# rank=1/stat_mult=1.0 — zero Focus so this file's exact flat-value assertions on stage 2/3
	# aren't also stat-scaled (same fix already applied to test_minion_lifecycle.gd/test_dew_minion.gd
	# for the same regression class, surfaced there by Tasks 1-2's stage-1 stat scaling instead).
	pc.base_stats.focus = 0
	pc.level = 3  # misfortune_minion (an extra ability) unlocks at level 3
	pc.weapon.base_damage = 0.0  # isolate the minion's own effects — no weapon-attack noise
	# Same durable TAUNT trick test_minion_lifecycle.gd/test_dew_minion.gd use: keeps the rat's real
	# attacks pinned on the PC so escalation isn't flaky.
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 999
	pc.attach_effect(taunt)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, encounter_id, "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()

	var enemy: Combatant = inst._enemies[0]
	if enemy.weapon != null:
		enemy.weapon.base_damage = 0.0

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "[%s] reached the Summoner's pre-spin window" % encounter_id)

	return [inst, pc, enemy]

## Stages Misfortune Minion (an EXTRA ability) on the Summoner's CURRENT turn, forces the summon
## reel to a single known-tier face, drives a real spin, and waits for it to settle. Returns
## nothing — callers read state off pc/enemy afterward.
func _stage_and_force_misfortune(inst: Combat, pc: Combatant, tier: ReelFace.ResultTier, label: String) -> void:
	inst._plan.toggle_extra_ability(&"misfortune_minion")
	_check(inst._plan.staged_extra_ability_id == &"misfortune_minion", "%s: Misfortune Minion staged via the real toggle_extra_ability()" % label)
	inst._commit_main1()
	_check(pc.summon_reel != null, "%s: commit appended a real summon_reel" % label)
	_check(pc.pending_minion_type == &"misfortune", "%s: pending_minion_type is &misfortune after committing Misfortune Minion" % label)

	var forced_face: ReelFace = null
	for f: ReelFace in pc.summon_reel.faces:
		if f.result_tier == tier:
			forced_face = f
			break
	_check(forced_face != null, "%s: found a face of the requested tier to force" % label)
	pc.summon_reel.faces = [forced_face]

	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "%s: the summon spin's strips settled without hanging" % label)

## Generic one-frame turn driver used while waiting for a non-Summoner event (the minion's own turn,
## or a later round) to occur (mirrors test_dew_minion.gd's _pump_one_frame exactly).
func _pump_one_frame(inst: Combat, pc: Combatant) -> void:
	if inst._awaiting_player_spin and inst._attacker == pc:
		inst._on_spin_pressed()
	elif inst._awaiting_end_turn and inst._attacker == pc:
		inst._on_end_turn_pressed()

## Stage/commit wiring: misfortune_minion is a real extra ability, costs 4 Mana, appends a real
## summon reel.
func _run_stage_commit_wiring() -> void:
	var summoner: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	summoner.level = 3  # misfortune_minion unlocks at level 3
	summoner.resource_pool.mana = 10
	var plan: MainPhasePlan = MainPhasePlan.new(summoner, summoner.ability_cost, 5, 2)
	_check(plan.can_stage_extra_ability(&"misfortune_minion"), "misfortune_minion stageable when affordable and unlocked")
	plan.toggle_extra_ability(&"misfortune_minion")
	_check(plan.staged_extra_ability_id == &"misfortune_minion", "misfortune_minion staged")
	var preview: Array[ActionReel] = plan.preview_reels()
	_check(not preview.is_empty() and not preview[preview.size() - 1].is_weapon_attack, "previewed misfortune summon reel is out of paylines")
	plan.commit()
	_check(summoner.summon_reel != null, "commit(): summon_reel is set")
	_check(summoner.resource_pool.mana == 10 - 4, "commit(): 4 Mana spent (got %d)" % summoner.resource_pool.mana)

## Real-spin end-to-end: summon a Misfortune Minion, force SUCCESS, verify all 3 stages debuff the
## enemy correctly and the minion expires after stage 3.
func _run_stage1_to_3_debuffs() -> void:
	var setup: Array = await _new_summoner_encounter(&"MisfortuneMinionStages")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]

	await _stage_and_force_misfortune(inst, pc, ReelFace.ResultTier.SUCCESS, "case1")

	# --- Case 1: stage 1 fires immediately in the summon's own spin — every enemy gets Weakened. ---
	_check(enemy.has_effect(&"weakened"), "case1: enemy has &weakened active immediately after stage 1")
	_check(not enemy.has_effect(&"sundered"), "case1: enemy does NOT have &sundered yet")
	_check(not enemy.has_effect(&"cursed"), "case1: enemy does NOT have &cursed yet")
	var minion: Combatant = pc.active_minion
	_check(minion != null and minion.is_alive(), "case1: active_minion is set and alive right after the summon")
	_check(minion.minion_type == &"misfortune", "case1: the summoned minion's minion_type is &misfortune (got %s)" % minion.minion_type)
	_check(minion.minion_stage == 1, "case1: minion_stage is 1 after its immediate stage-1 fire (got %d)" % minion.minion_stage)
	_check(inst._turn_manager.combatants.has(minion), "case1: the minion was appended to TurnManager.combatants")

	# --- Case 2: the minion's own turn fires stage 2 — Weakened is REAPPLIED, Sundered is added. ---
	inst._on_end_turn_pressed()
	var stage2_guard: int = 0
	while minion.minion_stage < 2 and stage2_guard < 3000:
		stage2_guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(minion.minion_stage == 2, "case2: minion_stage automatically became 2 on the minion's own turn (got %d)" % minion.minion_stage)
	_check(enemy.has_effect(&"weakened"), "case2: enemy STILL has &weakened (reapplied at stage 2)")
	_check(enemy.has_effect(&"sundered"), "case2: enemy now has &sundered")
	_check(not enemy.has_effect(&"cursed"), "case2: enemy does NOT have &cursed yet")
	_check(minion.is_alive(), "case2: the minion is still alive after stage 2")

	# --- Case 3: the minion's NEXT own turn fires stage 3 — Cursed is applied (flat dot_base_damage
	# matching EffectLibrary.make(&"cursed")'s own dot_fractions), then the minion expires. ---
	var stage3_guard: int = 0
	while minion.is_alive() and stage3_guard < 3000:
		stage3_guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(not minion.is_alive(), "case3: the minion is no longer alive after completing stage 3")
	_check(minion.minion_stage == 3, "case3: minion_stage is 3 (got %d)" % minion.minion_stage)
	_check(enemy.has_effect(&"cursed"), "case3: enemy has &cursed active")
	var curse: Effect = null
	for e: Effect in enemy.active_effects:
		if e != null and e.id == &"cursed":
			curse = e
			break
	var reference: Effect = EffectLibrary.make(&"cursed")
	_check(curse != null and curse.dot_base_damage == 12.0, "case3: cursed's dot_base_damage is flat 12.0 (got %s)" % (str(curse.dot_base_damage) if curse != null else "null"))
	_check(curse != null and curse.dot_fractions == reference.dot_fractions, "case3: cursed's dot_fractions match EffectLibrary.make(&cursed)'s own defaults (got %s vs %s)" % [str(curse.dot_fractions) if curse != null else "null", str(reference.dot_fractions)])
	_check(curse.dot_damage() == 6, "Misfortune stage-3 curse deals 6 damage/turn (got %d)" % curse.dot_damage())

	_check(pc.is_alive() and enemy.is_alive(), "case3: sanity — both the real PC and enemy are still alive")
	_check(not inst._turn_manager.is_combat_over(), "case3: is_combat_over() is false — the minion's own death did not trigger a loss/win check")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

func _initialize() -> void:
	_run_stage_commit_wiring()
	await _run_stage1_to_3_debuffs()

	print(("MISFORTUNE MINION TEST PASSED" if _failures == 0 else "MISFORTUNE MINION TEST FAILED: %d" % _failures))
	quit(_failures)
