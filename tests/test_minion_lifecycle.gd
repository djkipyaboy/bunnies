extends SceneTree

# Headless end-to-end test: the Ember Minion's real lifecycle (2026-08-16 minion-summoning-class
# spec §3, Task 7) — summon (forced SUCCESS and forced CRIT_SUCCESS outcomes), immediate stage-1
# damage, escalation to stage 2/3 on the minion's own subsequent turns, expiry after stage 3 or on
# fatal damage, and replacement when a second minion is summoned while one is active.
#
# Drives a REAL combat.tscn instance via the CombatHandoff entry point + roll_initiative_for_test()
# (mirrors tests/test_item_use_targeting_e2e.gd's exact harness), staging Ember Minion via the real
# MainPhasePlan.toggle_ability()/_commit_main1() and forcing the summon reel's landed face to a
# single known tier before spinning (the established technique for a deterministic reel outcome —
# see tests/test_combat_flee.gd's real-spin cases).
#
# The Summoner's own weapon.base_damage is zeroed right after building so its ordinary weapon-attack
# reels (which still spin alongside the summon reel every turn, and again on any later plain turn
# this test drives to keep the round advancing) never add noise to the enemy's HP — the ONLY damage
# source in these scenarios is the minion's own flat per-stage AoE, so every HP assertion below can
# be exact.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_minion_lifecycle.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a fresh CombatHandoff-driven combat.tscn instance with a Summoner PC (weapon damage
## zeroed) and one rat enemy, rolls initiative, and drives frames until it's the Summoner's own
## pre-spin window. Returns [inst, pc, enemy].
func _new_summoner_encounter(encounter_id: StringName) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	pc.base_stats.focus = 0
	pc.weapon.base_damage = 0.0  # isolate the minion's own damage — see file header
	# Final-review fix (2026-08-16 minion-summoning-class, Important #3) made the minion a real,
	# lowest-HP-tiebreak-eligible EnemyAI target once it exists — deliberately, per spec (enemies can
	# now choose to kill the minion instead of hitting a PC). That turns this whole file's every-HP-
	# assertion-is-exact escalation script flaky: the rat sometimes lands a real (unforced) attack on
	# the low-HP minion instead of the PC, killing it before its self-timed stage 2/3 fire. A durable
	# TAUNT (way past this test's frame guards) keeps the rat's real attacks pinned on the PC, exactly
	# reproducing the pre-fix guarantee, without touching EnemyAI's own targeting logic.
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

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "[%s] reached the Summoner's pre-spin window" % encounter_id)

	return [inst, pc, enemy]

## Stages Ember Minion on the Summoner's CURRENT turn (must already be at its pre-spin window),
## forces the summon reel to a single known-tier face, drives a real spin, and waits for it to
## settle. Returns nothing — callers read state off pc/enemy afterward.
func _stage_and_force_summon(inst: Combat, pc: Combatant, tier: ReelFace.ResultTier, label: String) -> void:
	inst._plan.toggle_ability()
	_check(inst._plan.ability_staged, "%s: Ember Minion staged via the real toggle_ability()" % label)
	inst._commit_main1()
	_check(pc.summon_reel != null, "%s: commit appended a real summon_reel" % label)

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
## or a later round) to occur: presses SPIN/END TURN for the Summoner's own plain turns (no ability
## staged — weapon damage is zeroed, so these turns are pure noise-free filler) and otherwise just
## lets the enemy/minion's own automatic turns run out on their timers.
func _pump_one_frame(inst: Combat, pc: Combatant) -> void:
	if inst._awaiting_player_spin and inst._attacker == pc:
		inst._on_spin_pressed()
	elif inst._awaiting_end_turn and inst._attacker == pc:
		inst._on_end_turn_pressed()

## Case 1-3: force a SUCCESS summon, verify immediate stage 1, then drive real turns/rounds to
## verify the minion's own turns fire stage 2 and stage 3 (with expiry) automatically.
func _run_summon_escalation_and_expiry() -> void:
	var setup: Array = await _new_summoner_encounter(&"MinionLifecycleEscalation")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]

	var hp_before_summon: int = enemy.hp
	await _stage_and_force_summon(inst, pc, ReelFace.ResultTier.SUCCESS, "case1")

	# --- Case 1: forced SUCCESS, stage 1 fires immediately (same spin, before any new round). ---
	_check(enemy.hp == hp_before_summon - Combat.MINION_BASE_STAGE_DAMAGE, "case1: enemy took stage-1 damage (%d) immediately in the summon's own spin (hp %d -> %d)" % [Combat.MINION_BASE_STAGE_DAMAGE, hp_before_summon, enemy.hp])
	var minion: Combatant = pc.active_minion
	_check(minion != null and minion.is_alive(), "case1: active_minion is set and alive right after the summon")
	_check(minion.minion_stage == 1, "case1: minion_stage is 1 after its immediate stage-1 fire (got %d)" % minion.minion_stage)
	_check(inst._turn_manager.combatants.has(minion), "case1: the minion was appended to TurnManager.combatants")

	# End the Summoner's turn and drive real frames until round 2 begins. The minion was appended
	# WITHOUT insert_acting_this_round(), so it must not act (minion_stage must not change) at any
	# point during the rest of round 1 — its first turn is next round only.
	#
	# round_before MUST be captured BEFORE ending the turn, not after: if the Summoner happened to
	# act SECOND in round 1 (enemy went first), _on_end_turn_pressed() synchronously exhausts round
	# 1's order and starts round 2 (including announcing round 2's first turn) before it returns —
	# reading round_number only after that call would already see round 2, silently turning this
	# "does not act during round 1" loop into a (trivially-passing, but meaningless) check of round
	# 2 instead. Debugged live: this caused a real ~intermittent flake where stage 2 fired inside
	# this loop and got misattributed to "round 1".
	var round_before: int = inst._turn_manager.round_number
	inst._on_end_turn_pressed()
	var acted_during_round1: bool = false
	var r2_guard: int = 0
	while inst._turn_manager.round_number == round_before and r2_guard < 2000:
		r2_guard += 1
		if minion.minion_stage != 1:
			acted_during_round1 = true
		_pump_one_frame(inst, pc)
		await process_frame
	_check(not acted_during_round1, "case1: the minion does not act during the remainder of round 1")
	_check(inst._turn_manager.round_number == round_before + 1, "case1: round 2 began within the frame guard (got %d)" % inst._turn_manager.round_number)

	# --- Case 2: the minion's own turn (now in round 2+) fires stage 2 automatically, no button. ---
	var hp_snapshot2: int = enemy.hp
	var stage2_guard: int = 0
	while minion.minion_stage < 2 and stage2_guard < 3000:
		stage2_guard += 1
		hp_snapshot2 = enemy.hp
		_pump_one_frame(inst, pc)
		await process_frame
	_check(minion.minion_stage == 2, "case2: minion_stage automatically became 2 on the minion's own turn (got %d)" % minion.minion_stage)
	_check(enemy.hp == hp_snapshot2 - Combat.MINION_BASE_STAGE_DAMAGE * 2, "case2: enemy took stage-2 damage (%d) automatically (hp %d -> %d)" % [Combat.MINION_BASE_STAGE_DAMAGE * 2, hp_snapshot2, enemy.hp])
	_check(minion.is_alive(), "case2: the minion is still alive after stage 2")

	# --- Case 3: the minion's NEXT own turn fires stage 3, dealing damage AND expiring the minion. ---
	var hp_snapshot3: int = enemy.hp
	var stage3_guard: int = 0
	while minion.is_alive() and stage3_guard < 3000:
		stage3_guard += 1
		hp_snapshot3 = enemy.hp
		_pump_one_frame(inst, pc)
		await process_frame
	_check(not minion.is_alive(), "case3: the minion is no longer alive after completing stage 3")
	_check(enemy.hp == hp_snapshot3 - Combat.MINION_BASE_STAGE_DAMAGE * 3, "case3: enemy took stage-3 damage (%d) before the minion expired (hp %d -> %d)" % [Combat.MINION_BASE_STAGE_DAMAGE * 3, hp_snapshot3, enemy.hp])
	_check(minion.minion_stage == 3, "case3: minion_stage is 3 (got %d)" % minion.minion_stage)

	# The minion's death must never gate combat-over — is_combat_over() must still reflect only the
	# real PC/enemy (Task 1's _living() is_minion exclusion, exercised end-to-end here).
	_check(pc.is_alive() and enemy.is_alive(), "case3: sanity — both the real PC and enemy are still alive")
	_check(not inst._turn_manager.is_combat_over(), "case3: is_combat_over() is false — the minion's own death did not trigger a loss/win check")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 4: a forced CRIT_SUCCESS summon builds the tankier minion variant.
func _run_crit_success_summon_is_tanky() -> void:
	var setup: Array = await _new_summoner_encounter(&"MinionLifecycleCrit")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]

	var hp_before_summon: int = enemy.hp
	await _stage_and_force_summon(inst, pc, ReelFace.ResultTier.CRIT_SUCCESS, "case4")

	_check(enemy.hp == hp_before_summon - Combat.MINION_BASE_STAGE_DAMAGE, "case4: stage 1 still fires immediately on a CRIT_SUCCESS summon")
	var minion: Combatant = pc.active_minion
	_check(minion != null and minion.is_alive(), "case4: active_minion is set and alive after a CRIT_SUCCESS summon")
	_check(minion.max_hp == MinionLibrary.TANKY_HP, "case4: CRIT_SUCCESS builds the tanky variant (max_hp %d, expected %d)" % [minion.max_hp, MinionLibrary.TANKY_HP])

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 5: summoning a second minion while one is already active expires the first and replaces it.
func _run_second_summon_replaces_first() -> void:
	var setup: Array = await _new_summoner_encounter(&"MinionLifecycleReplace")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]

	await _stage_and_force_summon(inst, pc, ReelFace.ResultTier.SUCCESS, "case5-first")
	var first_minion: Combatant = pc.active_minion
	_check(first_minion != null and first_minion.is_alive(), "case5: the first minion is active and alive")
	_check(first_minion.minion_stage == 1, "case5: the first minion is still on stage 1 (has not completed its stages)")

	inst._on_end_turn_pressed()

	# Drive real frames back to the Summoner's NEXT own turn. Minions sort into the turn order
	# purely by their own rolled initiative (playtest 2026-08-16 fixed a bug where they were
	# incorrectly forced acts_last) — so unlike an earlier draft of this test, we can no longer
	# assume the first minion is still on stage 1 by the time the Summoner acts again; it may have
	# already taken its own turn if it rolled higher initiative than the Summoner. That's fine —
	# what this case actually tests is REPLACEMENT (the old minion expires, a new one takes over),
	# which holds regardless of what stage the old minion had reached.
	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 2000:
		guard += 1
		_pump_one_frame(inst, pc)
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "case5: reached the Summoner's second pre-spin window")

	await _stage_and_force_summon(inst, pc, ReelFace.ResultTier.SUCCESS, "case5-second")

	_check(not first_minion.is_alive(), "case5: the FIRST minion is no longer alive (expired on replacement)")
	var second_minion: Combatant = pc.active_minion
	_check(second_minion != null and second_minion.is_alive(), "case5: active_minion now points at a new, alive minion")
	_check(second_minion != first_minion, "case5: the second minion is a genuinely different instance from the first")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Regression (2026-08-17 playtest): a minion killed by expiry or replacement must be removed
## from TurnManager.combatants, not just left dead in the list forever.
func _run_remove_dead_combatant_regression() -> void:
	var tm2: TurnManager = TurnManager.new()
	var caster2: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	var enemy2: Combatant = EnemyLibrary.make(&"rat")
	tm2.combatants = [caster2, enemy2]
	tm2.roll_initiative()
	var minion_a: Combatant = MinionLibrary.make(false, &"ember")
	caster2.active_minion = minion_a
	tm2.roll_initiative_for(minion_a)
	tm2.combatants.append(minion_a)
	_check(tm2.combatants.has(minion_a), "minion_a starts in TurnManager.combatants")
	minion_a.take_damage(minion_a.hp)
	tm2.remove_dead_combatant(minion_a)
	_check(not tm2.combatants.has(minion_a), "expired minion_a is removed from TurnManager.combatants (got size %d)" % tm2.combatants.size())

## Regression (2026-08-17 fix round 1 — task review Critical finding): removing the combatant the
## turn cursor is CURRENTLY pointed at (idx == _turn_index, the exact case a minion's own stage-3
## expiry hits during its own turn_started) must not skip the combatant scheduled to act right
## after it. Drives a REAL fixed order via begin()/advance_turn() (not a bare combatants.erase()
## check) so the _turn_index-adjustment branch in remove_dead_combatant() is actually exercised,
## per the task reviewer's exact reproduction trace: _order = [A, B, M, D], _turn_index pointing at
## M, remove M mid-turn, then advance_turn() must reach D, not skip straight to a new round.
func _run_remove_dead_combatant_cursor_regression() -> void:
	# One real player and one real enemy keep is_combat_over() false for the whole test (minions and
	# extra combatants are excluded from the living-count via is_minion / are just extra players).
	var a: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	var b: Combatant = EnemyLibrary.make(&"rat")
	var m: Combatant = MinionLibrary.make(false, &"ember")
	var d: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	a.current_initiative = 100
	b.current_initiative = 90
	m.current_initiative = 80
	d.current_initiative = 70

	var turns_seen: Array[Combatant] = []
	var tm3: TurnManager = TurnManager.new()
	tm3.combatants = [a, b, m, d]
	tm3.turn_started.connect(func(c: Combatant) -> void: turns_seen.append(c))

	tm3.begin()  # round 1: _order = [a, b, m, d] (sorted desc by current_initiative), _turn_index 0 -> a
	_check(turns_seen.size() == 1 and turns_seen[0] == a, "cursor-regression: round 1 opens on a")

	tm3.advance_turn()  # idx 0 -> 1 -> b
	_check(turns_seen.size() == 2 and turns_seen[1] == b, "cursor-regression: advance_turn reaches b")

	tm3.advance_turn()  # idx 1 -> 2 -> m (the case under test: cursor now AT m's own index)
	_check(turns_seen.size() == 3 and turns_seen[2] == m, "cursor-regression: advance_turn reaches m (cursor now at m's index)")

	# Simulate m's own stage-3 expiry firing DURING m's own turn_started, exactly like _take_minion_turn():
	# idx == _turn_index here (both 2) — the case the off-by-one guard originally missed.
	tm3.remove_dead_combatant(m)
	tm3.advance_turn()  # must land on d, not skip it and not roll into round 2 early
	_check(turns_seen.size() == 4 and turns_seen[3] == d, "cursor-regression: removing the CURRENT cursor's combatant (m) still lets d take its turn next, not skipped (got %s)" % [turns_seen[3].display_name if turns_seen.size() > 3 else "<none>"])

	# Sanity: a second round then opens cleanly (no leftover corruption from the removal).
	tm3.advance_turn()  # idx 3 -> 4 == _order.size() -> rolls into round 2, re-sorts [a, b, d]
	_check(turns_seen.size() == 5 and turns_seen[4] == a, "cursor-regression: round 2 opens correctly on a after the mid-round removal (got %s)" % [turns_seen[4].display_name if turns_seen.size() > 4 else "<none>"])

	# --- Companion case: removing an entry BEFORE the cursor still decrements correctly (no regression). ---
	var turns_seen2: Array[Combatant] = []
	var a2: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	var b2: Combatant = EnemyLibrary.make(&"rat")
	var m2: Combatant = MinionLibrary.make(false, &"ember")
	var d2: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	a2.current_initiative = 100
	b2.current_initiative = 90
	m2.current_initiative = 80
	d2.current_initiative = 70
	var tm4: TurnManager = TurnManager.new()
	tm4.combatants = [a2, b2, m2, d2]
	tm4.turn_started.connect(func(c: Combatant) -> void: turns_seen2.append(c))
	tm4.begin()          # idx 0 -> a2
	tm4.advance_turn()   # idx 1 -> b2
	tm4.advance_turn()   # idx 2 -> m2 (cursor now at m2)
	# Remove a2 (BEFORE the cursor) while the cursor sits on m2 — must decrement so the cursor still
	# logically tracks m2, and a subsequent advance_turn() must reach d2, not re-visit m2.
	tm4.remove_dead_combatant(a2)
	tm4.advance_turn()
	_check(turns_seen2.size() == 4 and turns_seen2[3] == d2, "cursor-regression (before-cursor case): removing a2 (before the cursor) still lets advance_turn reach d2 next (got %s)" % [turns_seen2[3].display_name if turns_seen2.size() > 3 else "<none>"])

	# --- Companion case: removing an entry AFTER the cursor causes no adjustment (no regression). ---
	var turns_seen3: Array[Combatant] = []
	var a3: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	var b3: Combatant = EnemyLibrary.make(&"rat")
	var m3: Combatant = MinionLibrary.make(false, &"ember")
	var d3: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	a3.current_initiative = 100
	b3.current_initiative = 90
	m3.current_initiative = 80
	d3.current_initiative = 70
	var tm5: TurnManager = TurnManager.new()
	tm5.combatants = [a3, b3, m3, d3]
	tm5.turn_started.connect(func(c: Combatant) -> void: turns_seen3.append(c))
	tm5.begin()          # idx 0 -> a3
	tm5.advance_turn()   # idx 1 -> b3 (cursor now at b3, BEFORE m3/d3)
	# Remove d3 (AFTER the cursor) — must NOT adjust the cursor; the next advance_turn() reaches m3.
	tm5.remove_dead_combatant(d3)
	tm5.advance_turn()
	_check(turns_seen3.size() == 3 and turns_seen3[2] == m3, "cursor-regression (after-cursor case): removing d3 (after the cursor) causes no cursor shift — advance_turn still reaches m3 next (got %s)" % [turns_seen3[2].display_name if turns_seen3.size() > 2 else "<none>"])

func _initialize() -> void:
	await _run_summon_escalation_and_expiry()
	await _run_crit_success_summon_is_tanky()
	await _run_second_summon_replaces_first()
	_run_remove_dead_combatant_regression()
	_run_remove_dead_combatant_cursor_regression()

	print(("MINION LIFECYCLE TEST PASSED" if _failures == 0 else "MINION LIFECYCLE TEST FAILED: %d" % _failures))
	quit(_failures)
