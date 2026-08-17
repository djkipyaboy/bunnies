extends SceneTree

# Headless end-to-end test for the "extra reel per turn" reel_surge buff + its 5-reel-cap overflow
# fallback (2026-08-16 summoner-ability-kit spec §6).
#
# Final-review fix (2026-08-17): the reel_surge cap check used to live in Combatant.begin_turn(),
# evaluated against ONLY the weapon baseline BEFORE any Main-1 ability/Ultimate added its own
# reel(s) that turn. Since no weapon carries 5+ baseline reels, the cap check there could never
# actually trip in real play (the overflow fallback was dead code), and worse, a real reel-adding
# ability staged the SAME turn (e.g. Flurry) could get wrongly blocked by MainPhasePlan's own cap
# check (which reads combatant.turn_reels.size()) because reel_surge had already grabbed a slot at
# begin_turn() time, before the player even chose an ability. The check now lives in combat.gd's
# _commit_main1(), evaluated AFTER every staged reel addition for the turn has committed. This
# file drives a REAL Skirmisher encounter (4-reel weapon baseline, own base ability Flurry adds a
# real 5th reel) through combat.tscn rather than unit-testing Combatant.begin_turn() in isolation,
# so the real MainPhasePlan/_commit_main1() interaction is what's actually exercised.
#
# Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a fresh CombatHandoff-driven combat.tscn instance with a Skirmisher PC (4-reel weapon
## baseline, own base ability &"flurry" adds a real reel) and one rat enemy, rolls initiative, and
## drives frames until it's the Skirmisher's own pre-spin window. Returns [inst, pc, enemy].
## (Mirrors tests/test_hasty_minion.gd's _new_summoner_encounter exactly, just a different class.)
func _new_skirmisher_encounter(encounter_id: StringName) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
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

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "[%s] reached the Skirmisher's pre-spin window" % encounter_id)

	return [inst, pc, enemy]

## Forces every reel in [param reels] to a single SUCCESS-tier face (mirrors
## test_hasty_minion.gd's _stage_and_force_hasty forced-face technique), so a real spin's outcome
## is deterministic instead of random.
func _force_all_success(reels: Array[ActionReel]) -> void:
	for reel: ActionReel in reels:
		var forced: ReelFace = null
		for f: ReelFace in reel.faces:
			if f.result_tier == ReelFace.ResultTier.SUCCESS:
				forced = f
				break
		if forced != null:
			reel.faces = [forced]

## Case 1 (under the cap, no ability staged): reel_surge alone splices a real extra reel onto the
## Skirmisher's 4-reel weapon baseline via the NEW post-_commit_main1() check.
func _run_under_cap() -> void:
	var setup: Array = await _new_skirmisher_encounter(&"ReelSurgeUnderCap")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]

	var weapon_reel_count: int = pc.weapon.reels.size()
	_check(weapon_reel_count == 4, "sanity: Skirmisher weapon baseline is 4 reels (got %d)" % weapon_reel_count)

	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	pc.attach_effect(buff)

	# No ability staged this turn — just the weapon baseline + reel_surge.
	inst._commit_main1()
	_check(pc.turn_reels.size() == weapon_reel_count + 1, "under-cap: reel_surge's post-commit check adds a real 5th reel (got %d)" % pc.turn_reels.size())
	_check(not pc.reel_surge_overflow_pending, "under-cap: no overflow flag when a real reel was added")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 2 (the real regression this bug caused): reel_surge attached AND Flurry (the Skirmisher's
## own reel-adding base ability) staged the SAME turn. Under the OLD begin_turn()-time check,
## reel_surge would have already grabbed a slot before Flurry was staged, pushing turn_reels to 5
## and making MainPhasePlan.can_stage_ability() (which reads combatant.turn_reels.size() >=
## reel_cap) wrongly refuse Flurry. Under the fix, Flurry stages freely and reel_surge's check
## (now evaluated AFTER commit) correctly finds the turn already at the cap and sets the overflow
## flag instead of a 6th reel. A forced-SUCCESS real spin also confirms the overflow damage-double
## fallback actually fires and logs (previously unreachable in real play).
func _run_at_cap_with_flurry() -> void:
	var setup: Array = await _new_skirmisher_encounter(&"ReelSurgeAtCapWithFlurry")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	enemy.weapon.base_damage = 0.0  # isolate this turn's own attack — no retaliation noise

	var weapon_reel_count: int = pc.weapon.reels.size()

	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	pc.attach_effect(buff)

	# Flurry must NOT be blocked by reel_surge even though reel_surge is already attached — the exact
	# regression. At this point (pre-commit) turn_reels is still the bare weapon baseline, since the
	# fix moved reel_surge's own check out of begin_turn().
	_check(pc.turn_reels.size() == weapon_reel_count, "pre-commit: turn_reels is still the bare weapon baseline (got %d)" % pc.turn_reels.size())
	_check(inst._plan.can_stage_ability(), "Flurry can still be staged with reel_surge attached (the regression this fix closes)")
	inst._plan.toggle_ability()
	_check(inst._plan.ability_staged, "Flurry successfully staged")

	inst._commit_main1()
	_check(pc.turn_reels.size() == weapon_reel_count + 1, "at-cap: turn_reels is weapon+Flurry only — reel_surge did NOT add a 6th reel (got %d)" % pc.turn_reels.size())
	_check(pc.turn_reels.size() == 5, "at-cap: turn_reels lands exactly on the 5-reel cap (got %d)" % pc.turn_reels.size())
	_check(pc.reel_surge_overflow_pending, "at-cap: the overflow flag IS set instead of a 6th reel")

	# Drive a real forced-SUCCESS spin to confirm the overflow fallback (double damage on the first
	# successful hit) actually fires and logs — previously unreachable in real play.
	_force_all_success(pc.turn_reels)
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the forced spin's strips settled without hanging")
	_check(not pc.reel_surge_overflow_pending, "the overflow flag is consumed by the first successful hit")

	var log_text: String = inst._log_box.get_parsed_text()
	_check(log_text.contains("reel surge overflow"), "the log records the reel-surge overflow's damage-double line")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

func _initialize() -> void:
	await _run_under_cap()
	await _run_at_cap_with_flurry()

	print(("REEL SURGE BUFF TEST PASSED" if _failures == 0 else "REEL SURGE BUFF TEST FAILED: %d" % _failures))
	quit(_failures)
