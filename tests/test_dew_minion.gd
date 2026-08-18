extends SceneTree

# Headless end-to-end test for Dew Minion (2026-08-16 summoner-ability-kit spec §2). Mirrors
# tests/test_minion_lifecycle.gd's exact CombatHandoff/force-a-reel-tier/frame-polling harness,
# adapted for Dew Minion being staged as an EXTRA ability (toggle_extra_ability()) rather than the
# Summoner's base ability (toggle_ability(), which Ember Minion uses).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dew_minion.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a fresh CombatHandoff-driven combat.tscn instance with a Summoner PC (weapon damage
## zeroed) and one rat enemy, rolls initiative, and drives frames until it's the Summoner's own
## pre-spin window. Returns [inst, pc, enemy]. (Mirrors test_minion_lifecycle.gd's
## _new_summoner_encounter exactly.)
func _new_summoner_encounter(encounter_id: StringName) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.level = 2  # dew_minion (an extra ability) unlocks at level 2
	pc.weapon.base_damage = 0.0  # isolate the minion's own effects — no weapon-attack noise
	# Same durable TAUNT trick test_minion_lifecycle.gd uses: keeps the rat's real attacks pinned on
	# the PC so escalation isn't flaky (the minion is a real, lowest-HP-tiebreak-eligible AI target).
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
	# Unlike test_minion_lifecycle.gd (which measures ENEMY hp, never the rat's own attack target),
	# this test measures the PC's own HP — and the durable taunt above keeps the rat's REAL,
	# unforced attacks landing on the PC every round. Zero the rat's own weapon damage too so those
	# attacks can't add noise to the heal-amount assertions below (mirrors the PC-weapon-zeroing
	# isolation technique, just on the other side).
	if enemy.weapon != null:
		enemy.weapon.base_damage = 0.0

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "[%s] reached the Summoner's pre-spin window" % encounter_id)

	return [inst, pc, enemy]

## Stages Dew Minion (an EXTRA ability, unlike Ember's base-ability slot) on the Summoner's CURRENT
## turn, forces the summon reel to a single known-tier face, drives a real spin, and waits for it
## to settle. Returns nothing — callers read state off pc/enemy afterward.
func _stage_and_force_dew(inst: Combat, pc: Combatant, tier: ReelFace.ResultTier, label: String) -> void:
	inst._plan.toggle_extra_ability(&"dew_minion")
	_check(inst._plan.staged_extra_ability_id == &"dew_minion", "%s: Dew Minion staged via the real toggle_extra_ability()" % label)
	inst._commit_main1()
	_check(pc.summon_reel != null, "%s: commit appended a real summon_reel" % label)
	_check(pc.pending_minion_type == &"dew", "%s: pending_minion_type is &dew after committing Dew Minion" % label)

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
## or a later round) to occur (mirrors test_minion_lifecycle.gd's _pump_one_frame exactly).
func _pump_one_frame(inst: Combat, pc: Combatant) -> void:
	if inst._awaiting_player_spin and inst._attacker == pc:
		inst._on_spin_pressed()
	elif inst._awaiting_end_turn and inst._attacker == pc:
		inst._on_end_turn_pressed()

## Stage/commit wiring: dew_minion is a real extra ability, costs 5 Mana, appends a real summon reel.
func _run_stage_commit_wiring() -> void:
	var summoner: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	summoner.level = 2  # dew_minion unlocks at level 2
	summoner.resource_pool.mana = 10
	var plan: MainPhasePlan = MainPhasePlan.new(summoner, summoner.ability_cost, 5, 2)
	_check(plan.can_stage_extra_ability(&"dew_minion"), "dew_minion stageable when affordable and unlocked")
	plan.toggle_extra_ability(&"dew_minion")
	_check(plan.staged_extra_ability_id == &"dew_minion", "dew_minion staged")
	var preview: Array[ActionReel] = plan.preview_reels()
	_check(not preview.is_empty() and not preview[preview.size() - 1].is_weapon_attack, "previewed dew summon reel is out of paylines")
	plan.commit()
	_check(summoner.summon_reel != null, "commit(): summon_reel is set")
	_check(summoner.resource_pool.mana == 10 - 5, "commit(): 5 Mana spent (got %d)" % summoner.resource_pool.mana)

## Real-spin end-to-end: summon a Dew Minion, force SUCCESS, verify stage 1 heals immediately.
func _run_stage1_immediate_heal() -> void:
	var setup: Array = await _new_summoner_encounter(&"DewMinionStage1")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]

	# Damage the PC first so the heal is observable.
	pc.take_damage(30)
	var hp_before_summon: int = pc.hp
	await _stage_and_force_dew(inst, pc, ReelFace.ResultTier.SUCCESS, "case1")

	_check(pc.hp == hp_before_summon + Combat.DEW_STAGE1_HEAL, "case1: PC healed for stage-1 amount (%d) immediately in the summon's own spin (hp %d -> %d)" % [Combat.DEW_STAGE1_HEAL, hp_before_summon, pc.hp])
	var minion: Combatant = pc.active_minion
	_check(minion != null and minion.is_alive(), "case1: active_minion is set and alive right after the summon")
	_check(minion.minion_type == &"dew", "case1: the summoned minion's minion_type is &dew (got %s)" % minion.minion_type)
	_check(minion.minion_stage == 1, "case1: minion_stage is 1 after its immediate stage-1 fire (got %d)" % minion.minion_stage)
	_check(inst._turn_manager.combatants.has(minion), "case1: the minion was appended to TurnManager.combatants")

	# --- Case 2 setup: attach a real debuff to the PC and capture the pre-stage-2 HP baseline
	# BEFORE ending the round-1 turn. This must happen before _on_end_turn_pressed() below, not
	# after: if the minion happens to be the very FIRST actor of round 2 (a real initiative-roll
	# race — minions sort into turn order purely by their own rolled initiative, same as
	# test_minion_lifecycle.gd's case5 comment notes), _take_minion_turn() fires stage 2
	# SYNCHRONOUSLY inside the single _on_end_turn_pressed() call, before this test ever gets
	# control back — so attaching the debuff or snapshotting hp any later would race it. ---
	var weakened: Effect = EffectLibrary.make(&"weakened")
	pc.attach_effect(weakened)
	_check(pc.has_effect(&"weakened"), "case2 setup: PC carries the weakened debuff before stage 2")
	var hp_before_stage2: int = pc.hp

	# End the Summoner's turn and drive real frames until the minion's own turn fires stage 2
	# (may already have happened synchronously inside _on_end_turn_pressed() itself — the loop
	# below is a no-op in that case, which is fine; it only needs to guarantee stage 2 has
	# happened by the time we check, not pin down exactly when).
	inst._on_end_turn_pressed()
	var stage2_guard: int = 0
	while minion.minion_stage < 2 and stage2_guard < 3000:
		stage2_guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(minion.minion_stage == 2, "case2: minion_stage automatically became 2 on the minion's own turn (got %d)" % minion.minion_stage)
	_check(pc.hp == mini(hp_before_stage2 + Combat.DEW_STAGE2_HEAL, pc.max_hp), "case2: PC healed by the stage-2 amount automatically (hp %d -> %d)" % [hp_before_stage2, pc.hp])
	_check(not pc.has_effect(&"weakened"), "case2: stage 2 cleansed the PC's oldest debuff")
	_check(minion.is_alive(), "case2: the minion is still alive after stage 2")

	# --- Case 3: the minion's NEXT own turn fires stage 3 — heal 16, cleanse (none left), attach
	# Thorns to every ally, then expire. ---
	var hp_snapshot3: int = pc.hp
	var stage3_guard: int = 0
	while minion.is_alive() and stage3_guard < 3000:
		stage3_guard += 1
		hp_snapshot3 = pc.hp
		_pump_one_frame(inst, pc)
		await process_frame
	_check(not minion.is_alive(), "case3: the minion is no longer alive after completing stage 3")
	_check(pc.hp == mini(hp_snapshot3 + Combat.DEW_STAGE3_HEAL, pc.max_hp), "case3: PC healed by the stage-3 amount (%d) before the minion expired (hp %d -> %d)" % [Combat.DEW_STAGE3_HEAL, hp_snapshot3, pc.hp])
	_check(minion.minion_stage == 3, "case3: minion_stage is 3 (got %d)" % minion.minion_stage)
	_check(pc.thorns_pct() > 0.0, "case3: the PC carries a Thorns buff after stage 3 (thorns_pct = %f)" % pc.thorns_pct())
	var log_text: String = inst._log_box.get_parsed_text()
	_check(log_text.contains("Thorns"), "case3: the log records the Thorns buff's application (playtest 2026-08-17 clarity fix)")

	_check(pc.is_alive() and enemy.is_alive(), "case3: sanity — both the real PC and enemy are still alive")
	_check(not inst._turn_manager.is_combat_over(), "case3: is_combat_over() is false — the minion's own death did not trigger a loss/win check")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Playtest 2026-08-18: a minion holding a SHIELDED buff at its stage-3 expiry absorbed the
## self-damage take_damage(minion.hp) applies, so hp never reached 0 and [signal defeated] never
## fired — the minion vanished from turn order (remove_dead_combatant runs unconditionally) but its
## panel (gated on the defeated signal) stayed visible forever. Expiry must guarantee death
## regardless of shield.
func _run_stage3_expiry_bypasses_shield() -> void:
	var setup: Array = await _new_summoner_encounter(&"DewMinionShieldExpiry")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	await _stage_and_force_dew(inst, pc, ReelFace.ResultTier.SUCCESS, "shield_case")

	var minion: Combatant = pc.active_minion
	_check(minion != null and minion.is_alive(), "shield_case: minion summoned and alive")
	minion.minion_stage = 2
	minion.apply_shield(999, 5)
	_check(minion.shield_hp == 999, "shield_case: minion carries a 999 HP shield before its stage-3 turn")

	inst._run_minion_stage(minion, 3)

	_check(not minion.is_alive(), "shield_case: minion is dead after stage-3 expiry despite the shield (hp=%d, shield_hp=%d)" % [minion.hp, minion.shield_hp])
	_check(not inst._turn_manager.combatants.has(minion), "shield_case: minion removed from TurnManager.combatants")
	_check(inst._panels.has(minion) and not (inst._panels[minion] as CombatantPanel).visible, "shield_case: minion's panel is hidden")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

func _initialize() -> void:
	_run_stage_commit_wiring()
	await _run_stage1_immediate_heal()
	await _run_stage3_expiry_bypasses_shield()

	print(("DEW MINION TEST PASSED" if _failures == 0 else "DEW MINION TEST FAILED: %d" % _failures))
	quit(_failures)
