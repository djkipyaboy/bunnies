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
	pc.base_stats.focus = 0  # keep ability_magnitude_multiplier() == 1.0 so damage assertions below
	# aren't also stat-scaled on top of the rank-2 (MAX_LEVEL) values these talent tests exercise.
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
	# pc is at MAX_LEVEL (rank 2) with Focus zeroed above, so stage 1 uses the rank-2 per-stage
	# damage (12, not rank 1's 8) at a 1.0 stat multiplier — see MINION_EMBER_STAGE_DAMAGE_RANK2.
	inst._run_minion_stage(minion, 1, pc)  # stage 1 = 12 rank-2 base damage, echo = 6
	_check(pc.pending_delayed_bloom_damage == 6, "ember_delayed_bloom: queued a 6-damage echo (50%% of 12) (got %d)" % pc.pending_delayed_bloom_damage)
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
	# 100 (not rank-1-era 50): must survive BOTH the rank-2 stage-3 base hit (32) AND the overkill
	# splash (27) — 50 would be overkilled itself and die before the mechanic could be observed.
	var bystander: Combatant = Combatant.new()
	bystander.base_max_hp = 100; bystander.apply_stats(); bystander.start_combat()
	inst._enemies = [victim, bystander]
	# _run_minion_stage's damage path reads targets via _enemies_of(), which pulls from
	# _turn_manager.combatants (not _enemies) — both must be kept in sync so the fresh
	# victim/bystander pair (not the real "rat" from setup) are the ones actually hit.
	var combatants: Array[Combatant] = [pc, victim, bystander]
	inst._turn_manager.combatants = combatants
	# pc is at MAX_LEVEL (rank 2) with Focus zeroed above, so stage 3 uses the rank-2 per-stage
	# damage (32, not rank 1's 24) at a 1.0 stat multiplier.
	inst._run_minion_stage(minion, 3, pc)  # stage 3 = 32 damage; victim has 5 HP -> 27 overkill
	_check(not victim.is_alive(), "ember_overripe setup: the low-HP victim died to the stage-3 burst")
	# bystander is also a live enemy of the same AoE burst, so it eats the base 32 dmg from the
	# main loop PLUS the 27 overkill splash -> 59 total (not just the 27 splash in isolation).
	_check(bystander.hp == bystander.max_hp - 59, "ember_overripe: overkill splashed onto the bystander on top of its own base hit (got %d/%d)" % [bystander.hp, bystander.max_hp])
	inst.queue_free()

## Generic one-frame turn driver used while waiting for a non-caster event (the enemy's own turn,
## or a later round) to occur (mirrors test_dew_minion.gd's/test_hasty_minion.gd's _pump_one_frame
## exactly).
func _pump_one_frame(inst: Combat, pc: Combatant) -> void:
	if inst._awaiting_player_spin and inst._attacker == pc:
		inst._on_spin_pressed()
	elif inst._awaiting_end_turn and inst._attacker == pc:
		inst._on_end_turn_pressed()

## Review finding fix (2026-08-24 Task 4 review): the existing _test_delayed_bloom_echo above only
## asserts the field is queued after _run_minion_stage() runs — it never drives a real phase
## transition to UPKEEP, so the UPKEEP handler in combat.gd's _on_phase_changed() (which actually
## applies the echo damage and clears the field) was unverified. UPKEEP fires automatically and
## synchronously at the START of every combatant's own turn (PhaseManager.start_turn() -> UPKEEP ->
## MAIN_1, called from combat.gd's _on_turn_started()) — so the queued echo, set immediately after
## combat starts (i.e. after pc's FIRST Upkeep already ran with pending_delayed_bloom_damage == 0),
## is only consumed at pc's NEXT own Upkeep. Drive a full turn cycle (through the enemy's turn, then
## back to pc) using the same _pump_one_frame guarded-loop pattern test_hasty_minion.gd/
## test_dew_minion.gd use, so a fresh Upkeep genuinely fires for pc before asserting.
func _test_delayed_bloom_upkeep_consumption() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	pc.weapon.base_damage = 0.0  # isolate the echo — pc's own spin must not also damage the enemy
	var enemy: Combatant = inst._enemies[0]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_delayed_bloom"), "picks ember_delayed_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	# pc is at MAX_LEVEL (rank 2) with Focus zeroed above, so stage 1 uses the rank-2 per-stage
	# damage (12, not rank 1's 8) at a 1.0 stat multiplier.
	inst._run_minion_stage(minion, 1, pc)  # stage 1 = 12 rank-2 base damage, echo = 6
	_check(pc.pending_delayed_bloom_damage == 6, "setup: queued a 6-damage echo before driving to Upkeep")

	var hp_before: int = enemy.hp
	# Drive frames through a full turn cycle (the enemy's turn, then back to pc's own turn) so pc's
	# NEXT Upkeep actually fires and consumes the queued echo.
	var seen_enemy_turn: bool = false
	var guard: int = 0
	while guard < 6000:
		guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
		if inst._attacker != null and inst._attacker != pc:
			seen_enemy_turn = true
		if seen_enemy_turn and inst._awaiting_player_spin and inst._attacker == pc:
			break
	_check(seen_enemy_turn and inst._awaiting_player_spin and inst._attacker == pc, "reached pc's next own turn (a fresh Upkeep) after the enemy acted")
	_check(enemy.hp == hp_before - 6, "ember_delayed_bloom: the Upkeep echo dealt 6 damage to the enemy (got %d, expected %d)" % [enemy.hp, hp_before - 6])
	_check(pc.pending_delayed_bloom_damage == 0, "ember_delayed_bloom: pending_delayed_bloom_damage was cleared after Upkeep consumed it")
	inst.queue_free()

## 2026-09-02 fix: on a REAL stage-2/3 minion turn, _take_minion_turn() calls _run_minion_stage()
## with NO caster (only stage 1 passes one) — Delayed Bloom's echo-queueing line still checked
## `caster != null` after the owner-resolution fix (C1) had already updated the talent-detection
## line above it, so the echo silently never queued past stage 1. This drives that exact
## caster-omitted path directly (no `pc` argument) to prove the echo now queues via
## minion.minion_caster fallback.
func _test_delayed_bloom_echo_on_real_stage2_turn() -> void:
	var setup: Array = await _new_combat_with_harvester()
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	_check(pc.pick_ability_talent(&"base_ability", &"ember_delayed_bloom"), "picks ember_delayed_bloom")
	var minion: Combatant = MinionLibrary.make(false, &"ember")
	minion.minion_caster = pc
	# No caster argument — mirrors _take_minion_turn()'s real stage-2/3 call exactly.
	# pc is at MAX_LEVEL (rank 2) with Focus zeroed, so stage 2 uses the rank-2 per-stage damage
	# (22, not rank 1's 16) at a 1.0 stat multiplier -> echo = 11.
	inst._run_minion_stage(minion, 2)
	_check(pc.pending_delayed_bloom_damage == 11, "ember_delayed_bloom: queued an 11-damage echo (50%% of 22) on a real caster-omitted stage-2 turn (got %d)" % pc.pending_delayed_bloom_damage)
	inst.queue_free()

func _initialize() -> void:
	await _test_overgrown_roots()
	await _test_no_talent_no_rooted()
	await _test_delayed_bloom_echo()
	await _test_overripe_splashes_overkill()
	await _test_delayed_bloom_upkeep_consumption()
	await _test_delayed_bloom_echo_on_real_stage2_turn()
	quit(_failures)
