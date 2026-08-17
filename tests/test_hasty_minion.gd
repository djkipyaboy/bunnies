extends SceneTree

# Headless end-to-end test for Hasty Minion (2026-08-16 summoner-ability-kit spec §2). Mirrors
# tests/test_dew_minion.gd's/test_misfortune_minion.gd's exact CombatHandoff/force-a-reel-tier/
# frame-polling harness, adapted for Hasty Minion being staged as an EXTRA ability
# (toggle_extra_ability()) that party-wide BUFFS every ALLY (not heal/debuff) across its 3 stages.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hasty_minion.gd

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
	pc.level = 4  # hasty_minion (an extra ability) unlocks at level 4
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

## Stages Hasty Minion (an EXTRA ability) on the Summoner's CURRENT turn, forces the summon reel
## to a single known-tier face, drives a real spin, and waits for it to settle. Returns nothing —
## callers read state off pc/enemy afterward.
func _stage_and_force_hasty(inst: Combat, pc: Combatant, tier: ReelFace.ResultTier, label: String) -> void:
	inst._plan.toggle_extra_ability(&"hasty_minion")
	_check(inst._plan.staged_extra_ability_id == &"hasty_minion", "%s: Hasty Minion staged via the real toggle_extra_ability()" % label)
	inst._commit_main1()
	_check(pc.summon_reel != null, "%s: commit appended a real summon_reel" % label)
	_check(pc.pending_minion_type == &"hasty", "%s: pending_minion_type is &hasty after committing Hasty Minion" % label)

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

## Stage/commit wiring: hasty_minion is a real extra ability, costs 6 Mana, appends a real summon reel.
func _run_stage_commit_wiring() -> void:
	var summoner: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	summoner.level = 4  # hasty_minion unlocks at level 4
	summoner.resource_pool.mana = 10
	var plan: MainPhasePlan = MainPhasePlan.new(summoner, summoner.ability_cost, 5, 2)
	_check(plan.can_stage_extra_ability(&"hasty_minion"), "hasty_minion stageable when affordable and unlocked")
	plan.toggle_extra_ability(&"hasty_minion")
	_check(plan.staged_extra_ability_id == &"hasty_minion", "hasty_minion staged")
	var preview: Array[ActionReel] = plan.preview_reels()
	_check(not preview.is_empty() and not preview[preview.size() - 1].is_weapon_attack, "previewed hasty summon reel is out of paylines")
	plan.commit()
	_check(summoner.summon_reel != null, "commit(): summon_reel is set")
	_check(summoner.resource_pool.mana == 10 - 6, "commit(): 6 Mana spent (got %d)" % summoner.resource_pool.mana)

## Finds the active INITIATIVE_MOD effect (if any) on [param who] whose magnitude matches
## [param expect_mag], for asserting stage 1's +20 Initiative buff precisely.
func _find_initiative_mod(who: Combatant, expect_mag: float) -> Effect:
	for e: Effect in who.active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD and is_equal_approx(e.magnitude, expect_mag):
			return e
	return null

## Real-spin end-to-end: summon a Hasty Minion, force SUCCESS, verify all 3 stages buff the party
## correctly (Initiative -> regen -> Empowered+reel_surge) and the minion expires after stage 3.
func _run_stage1_to_3_buffs() -> void:
	var setup: Array = await _new_summoner_encounter(&"HastyMinionStages")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]

	await _stage_and_force_hasty(inst, pc, ReelFace.ResultTier.SUCCESS, "case1")

	# --- Case 1: stage 1 fires immediately in the summon's own spin — every ally gets +20
	# Initiative for 3 turns. Final-review fix (2026-08-17): stage 1 fires SYNCHRONOUSLY inside the
	# summoning caster's own Combat phase, so the caster's own upcoming End phase ticks this buff
	# once immediately this same turn — the caster specifically gets +1 duration (4, not 3) so it
	# still benefits over 3 FRESH turns, same as every other ally who hasn't acted yet this round
	# (mirrors the identical fix already applied to Grand Sacrifice's Hasty variant/Dew's Thorns). pc
	# IS the summoning caster here, so it's the +1 case. ---
	var haste_effect: Effect = _find_initiative_mod(pc, 20.0)
	_check(haste_effect != null, "case1: PC has an INITIATIVE_MOD effect with magnitude +20 immediately after stage 1")
	_check(haste_effect != null and haste_effect.duration == 4, "case1: the +20 Initiative buff has duration 4 for the caster (3 base + 1 caster-tick-timing fix, got %s)" % (str(haste_effect.duration) if haste_effect != null else "null"))
	_check(pc._effect_regen_bonus() == 0, "case1: no regen bonus yet")
	_check(not pc.has_effect(&"empowered"), "case1: PC does NOT have &empowered yet")
	_check(not pc.has_effect(&"reel_surge"), "case1: PC does NOT have &reel_surge yet")
	var minion: Combatant = pc.active_minion
	_check(minion != null and minion.is_alive(), "case1: active_minion is set and alive right after the summon")
	_check(minion.minion_type == &"hasty", "case1: the summoned minion's minion_type is &hasty (got %s)" % minion.minion_type)
	_check(minion.minion_stage == 1, "case1: minion_stage is 1 after its immediate stage-1 fire (got %d)" % minion.minion_stage)
	_check(inst._turn_manager.combatants.has(minion), "case1: the minion was appended to TurnManager.combatants")

	# --- Case 2: the minion's own turn fires stage 2 — Initiative buff is REAPPLIED, resource-regen
	# buff (regen_bonus == 3) is added. ---
	inst._on_end_turn_pressed()
	var stage2_guard: int = 0
	while minion.minion_stage < 2 and stage2_guard < 3000:
		stage2_guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(minion.minion_stage == 2, "case2: minion_stage automatically became 2 on the minion's own turn (got %d)" % minion.minion_stage)
	_check(_find_initiative_mod(pc, 20.0) != null, "case2: PC STILL has the +20 Initiative buff (reapplied at stage 2)")
	_check(pc._effect_regen_bonus() == 3, "case2: PC now has a regen_bonus of 3 (got %d)" % pc._effect_regen_bonus())
	_check(not pc.has_effect(&"empowered"), "case2: PC does NOT have &empowered yet")
	_check(not pc.has_effect(&"reel_surge"), "case2: PC does NOT have &reel_surge yet")
	_check(minion.is_alive(), "case2: the minion is still alive after stage 2")
	var log_text_stage2: String = inst._log_box.get_parsed_text()
	_check(log_text_stage2.contains("resource regen"), "case2: the log records the resource-regen buff's application (playtest 2026-08-17 clarity fix)")

	# --- Case 3: the minion's NEXT own turn fires stage 3 — Empowered (1 turn) + reel_surge
	# (3 turns) are applied, then the minion expires. ---
	var stage3_guard: int = 0
	while minion.is_alive() and stage3_guard < 3000:
		stage3_guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(not minion.is_alive(), "case3: the minion is no longer alive after completing stage 3")
	_check(minion.minion_stage == 3, "case3: minion_stage is 3 (got %d)" % minion.minion_stage)
	_check(pc.has_effect(&"empowered"), "case3: PC has &empowered active")
	var empowered: Effect = null
	for e: Effect in pc.active_effects:
		if e != null and e.id == &"empowered":
			empowered = e
			break
	_check(empowered != null and empowered.duration == 1, "case3: &empowered's duration is locked to 1 turn regardless of EffectLibrary's own default (got %s)" % (str(empowered.duration) if empowered != null else "null"))
	_check(pc.has_effect(&"reel_surge"), "case3: PC has &reel_surge active")

	_check(pc.is_alive() and enemy.is_alive(), "case3: sanity — both the real PC and enemy are still alive")
	_check(not inst._turn_manager.is_combat_over(), "case3: is_combat_over() is false — the minion's own death did not trigger a loss/win check")

	# --- Case 4: drive one more real full turn for the PC. Final-review fix (2026-08-17): the
	# reel_surge cap check moved from Combatant.begin_turn() to combat.gd's _commit_main1(), run
	# AFTER this turn's staged reel additions commit — so at the bare pre-spin window (before the
	# player has pressed Spin) turn_reels is still just the weapon baseline; the extra reel only
	# appears once _commit_main1() actually runs. Drive a real _on_spin_pressed() (rather than
	# asserting on the pre-commit state, which the old test did via begin_turn() directly) to
	# exercise the real post-commit check. ---
	var weapon_reel_count: int = pc.weapon.reels.size()
	while not (inst._awaiting_player_spin and inst._attacker == pc) and stage3_guard < 6000:
		stage3_guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "case4: reached the PC's next real pre-spin window")
	_check(pc.turn_reels.size() == weapon_reel_count, "case4: pre-commit turn_reels is still the bare weapon baseline (got %d)" % pc.turn_reels.size())

	inst._on_spin_pressed()
	_check(not pc.reel_surge_overflow_pending, "case4: PC is well under the 5-reel cap, so no overflow flag is set")
	_check(pc.turn_reels.size() == weapon_reel_count + 1, "case4: reel_surge added a real extra reel this turn after _commit_main1() (weapon baseline %d, got %d)" % [weapon_reel_count, pc.turn_reels.size()])

	var spin_guard4: int = 0
	while inst._pending_strips > 0 and spin_guard4 < 2000:
		spin_guard4 += 1
		await process_frame
	_check(inst._pending_strips <= 0, "case4: the spin's strips settled without hanging")

	# --- Case 5 (final-review fix, 2026-08-17): construct a realistic overflow scenario rather than
	# leaving the overflow fallback exercised only by a synthetic begin_turn() unit test. reel_surge
	# is still active (3 turns from stage 3, ticked once by case 4's own End phase) — grow the
	# Summoner's own weapon baseline to 5 reels for this turn so the turn is ALREADY at the 5-cap
	# before reel_surge's post-_commit_main1() check runs, then drive a real spin through the actual
	# _on_spin_pressed()/_commit_main1() pipeline and confirm the double-damage overflow fallback
	# fires. Growing the weapon (rather than stacking real reel-adding abilities the Summoner's own
	# kit doesn't have outside minions) is the least-synthetic way to reach a genuine 5-reel turn
	# with this class while still exercising the real orchestrator code path end-to-end. ---
	_check(pc.has_effect(&"reel_surge"), "case5 precondition: reel_surge is still active going into this turn")
	while pc.weapon.reels.size() < 5:
		pc.weapon.reels.append(pc.weapon.reels[0].duplicate())
	_check(pc.weapon.reels.size() == 5, "case5: weapon baseline grown to 5 reels (got %d)" % pc.weapon.reels.size())

	while not (inst._awaiting_player_spin and inst._attacker == pc) and stage3_guard < 9000:
		stage3_guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "case5: reached the PC's next real pre-spin window")
	_check(pc.turn_reels.size() == 5, "case5: begin_turn() seeded turn_reels from the now-5-reel weapon baseline (got %d)" % pc.turn_reels.size())

	inst._on_spin_pressed()
	_check(pc.reel_surge_overflow_pending, "case5: reel_surge's post-commit check correctly sets the overflow flag at the real 5-reel cap")
	_check(pc.turn_reels.size() == 5, "case5: no 6th reel was appended (got %d)" % pc.turn_reels.size())

	var spin_guard5: int = 0
	while inst._pending_strips > 0 and spin_guard5 < 2000:
		spin_guard5 += 1
		await process_frame
	_check(inst._pending_strips <= 0, "case5: the spin's strips settled without hanging")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Regression repro (2026-08-17 playtest): does a Hasty-buffed minion whose current_initiative
## exceeds 100 still get a turn? Force a high base roll so the +20 buff pushes it over 100.
func _run_over_100_initiative_repro() -> void:
	var tm3: TurnManager = TurnManager.new()
	var caster3: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	var enemy3: Combatant = EnemyLibrary.make(&"rat")
	tm3.combatants = [caster3, enemy3]
	tm3.roll_initiative()
	var hasty3: Combatant = MinionLibrary.make(false, &"hasty")
	hasty3.base_initiative = 95  # force high; +20 Hasty buff will push current_initiative to 115
	hasty3.recompute_initiative()
	var haste_buff := Effect.new()
	haste_buff.id = &"hasty_initiative"
	haste_buff.kind = Effect.Kind.INITIATIVE_MOD
	haste_buff.magnitude = 20.0
	haste_buff.duration = 3
	haste_buff.beneficial = true
	hasty3.attach_effect(haste_buff)
	_check(hasty3.current_initiative > 100, "test setup: current_initiative is actually over 100 (got %d)" % hasty3.current_initiative)
	tm3.combatants.append(hasty3)
	tm3.begin()
	var order3: Array[Combatant] = tm3.get_turn_order()
	_check(order3.has(hasty3), "a >100-current_initiative minion still appears in get_turn_order() (size %d)" % order3.size())
	_check(order3[0] == hasty3, "it sorts to the FRONT of turn order, not dropped (front is %s)" % order3[0].display_name)

func _initialize() -> void:
	_run_stage_commit_wiring()
	_run_over_100_initiative_repro()
	await _run_stage1_to_3_buffs()

	print(("HASTY MINION TEST PASSED" if _failures == 0 else "HASTY MINION TEST FAILED: %d" % _failures))
	quit(_failures)
