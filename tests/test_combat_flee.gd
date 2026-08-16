extends SceneTree

# Headless test for the Flee combat option's post-spin routing (2026-08-16 spec §1). Mirrors
# tests/test_combat_win_recovery.gd's exact handoff-harness pattern — sets the routing flag
# directly rather than driving a real spin, since _resolve_handoff_continue()'s branching is
# what this task actually changes. Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_flee.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# --- Fled encounter: no mark_defeated, no recovery/defeat-reset, routes like a win, label reads FLED! ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.hp = pc.max_hp - 50  # damaged; a WIN would normally partially recover this — Flee must NOT
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	var return_path: String = "res://world/overworld_demo.tscn"
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"OverworldRat", return_path, Vector2(1.0, 2.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var hp_before: int = pc.hp
	inst._on_combat_fled()  # simulates a successful Flee's post-spin call, same call site _finish_spin() uses
	var label: Label = inst._overlay.get_node("ResultLabel")
	_check(label.text == "FLED!", "result label reads FLED! (got: %s)" % label.text)

	var path: String = inst.press_continue_for_test()
	_check(path == return_path, "fled encounter routes to return_scene_path, same as a win (got: %s)" % path)
	_check(pc.hp == hp_before, "fled PC gets NO post-combat recovery (before %d, after %d)" % [hp_before, pc.hp])
	_check(not CombatHandoff.is_defeated(&"OverworldRat"), "fled encounter is NOT marked defeated (can be re-fought)")

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- Sanity: a REAL win still marks defeated + recovers, proving the new _fled_this_encounter
	# branch didn't regress the existing win path (test_combat_win_recovery.gd covers this in more
	# depth; this is a lighter smoke check specific to the branch this task edited). ---
	var win_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	win_pc.hp = win_pc.max_hp - 50
	CombatHandoff.begin_encounter(win_pc, [], inv, vault, enemy_ids, &"OverworldRat2", return_path, Vector2(1.0, 2.0))
	var win_scene: PackedScene = load("res://combat/combat.tscn")
	var win_inst: Combat = win_scene.instantiate()
	get_root().add_child(win_inst)
	await process_frame
	await process_frame
	var win_hp_before: int = win_pc.hp
	win_inst._last_result_won = true
	win_inst.press_continue_for_test()
	_check(win_pc.hp > win_hp_before, "sanity: a real win still recovers HP (before %d, after %d)" % [win_hp_before, win_pc.hp])
	_check(CombatHandoff.is_defeated(&"OverworldRat2"), "sanity: a real win still marks the encounter defeated")
	win_inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- Kill-then-Flee: XP/Amber/Loot from an enemy defeated EARLIER in the same fight must be
	# fully REVERTED by a later successful Flee (2026-08-16 review findings, Critical #1 + #2) —
	# not merely suppressed from the result label. Drives a REAL kill via take_damage(9999), the
	# same signal->_on_enemy_defeated() path a win uses, so this actually exercises the permanent
	# pc.xp/_party_inventory.amber/bag mutation, not a synthetic shortcut. The bag is pre-filled to
	# capacity so the kill's loot roll is forced to overflow, proving the overflow-ground-drop leak
	# (Critical #2) is also closed. ---
	CombatHandoff.clear_pending()
	var kf_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var kf_inv: PartyInventory = PartyInventory.new()
	var kf_vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(kf_pc, [], kf_inv, kf_vault, enemy_ids, &"OverworldRatKillFlee", return_path, Vector2(1.0, 2.0))
	var kf_scene: PackedScene = load("res://combat/combat.tscn")
	var kf_inst: Combat = kf_scene.instantiate()
	get_root().add_child(kf_inst)
	await process_frame
	await process_frame

	# Fill the bag to capacity BEFORE the kill so the kill's loot roll has nowhere to go and lands
	# in _fight_overflow_items instead of the bag.
	while kf_inv.can_add_to_bag():
		kf_inv.gear.append(Gear.new())

	# Force a deterministic Gear drop (the rat's real "overworld_trash" table rolls probabilistically,
	# which would make this test flaky) so the overflow path is guaranteed to trigger.
	var deterministic_loot: LootTable = LootTable.new()
	var forced_entry: LootEntry = LootEntry.new()
	var dropped_gear: Gear = Gear.new()
	dropped_gear.display_name = "Test Dropped Gear"
	forced_entry.item = dropped_gear
	forced_entry.drop_chance = 1.0
	deterministic_loot.entries = [forced_entry]
	kf_inst._enemies[0].loot_table = deterministic_loot

	var kf_xp_before: int = kf_pc.xp
	var kf_amber_before: int = kf_inv.amber
	var kf_bag_count_before: int = kf_inv.bag_count()

	kf_inst._enemies[0].take_damage(9999)  # a REAL kill -> the real _on_enemy_defeated() path
	_check(not kf_inst._enemies[0].is_alive(), "kill-then-flee: the rat is actually dead")
	_check(kf_pc.xp == kf_xp_before + Combat.ENEMY_XP_REWARD, "kill-then-flee: XP was actually granted at kill-time (got %d)" % kf_pc.xp)
	_check(kf_inv.amber == kf_amber_before + 5, "kill-then-flee: Amber was actually granted at kill-time (got %d)" % kf_inv.amber)
	_check(not kf_inst._fight_overflow_items.is_empty(), "kill-then-flee: the loot overflowed the full bag (sanity check on the test setup itself)")

	kf_inst._on_combat_fled()
	_check(kf_pc.xp == kf_xp_before, "kill-then-flee: Flee reverts the earlier kill's XP (before %d, after %d)" % [kf_xp_before, kf_pc.xp])
	_check(kf_inv.amber == kf_amber_before, "kill-then-flee: Flee reverts the earlier kill's Amber (before %d, after %d)" % [kf_amber_before, kf_inv.amber])
	_check(kf_inv.bag_count() == kf_bag_count_before, "kill-then-flee: Flee reverts any bag-granted loot (before %d, after %d)" % [kf_bag_count_before, kf_inv.bag_count()])

	kf_inst.press_continue_for_test()
	_check(CombatHandoff.pending_ground_drops.is_empty(), "kill-then-flee: overflow loot from the earlier kill does NOT leak through as a ground drop on Flee")

	kf_inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- Real-spin regression (2026-08-16 final-review fix wave, Critical #1): staging Flee then
	# actually driving a real SPIN must not throw a script error or hang, for BOTH outcome tiers.
	# Everything above only ever called _on_combat_fled() directly, which is exactly the gap the
	# final review found — it never actually exercised _do_spin()/PaylineLibrary/PaylineResolver
	# with Flee's 0-weapon-attack-reel loadout (Flee's reel has is_weapon_attack = false, so
	# _weapon_attack_count() returns 0). Before the fix, PaylineLibrary.lines_for(0) hands back 3
	# EMPTY row-lines and PaylineResolver.evaluate() indexes line[0] on one of them — a runtime
	# error.
	#
	# Uses the fully-manual harness established by tests/test_darkness_rampage.gd (build a bare
	# combat.tscn instance, then assign _pcs/_enemies/_turn_manager.combatants/_panels/_attacker/
	# _defender/_plan directly) rather than the CombatHandoff-driven harness used above: the
	# CombatHandoff path lets the scene's OWN turn-start machinery run too (whichever combatant
	# wins initiative gets a real turn immediately), and if the enemy wins that roll it arms a
	# real ENEMY_THINK_DELAY timer bound to _do_spin() — which then fires in the background WHILE
	# this test is polling _pending_strips, calling _do_spin() a second unwanted time against the
	# by-then-overridden _attacker and re-connecting strip_settled on already-connected strips (a
	# real "Signal already connected" engine error, confirmed live while drafting this test). The
	# fully-manual harness never starts that turn machinery in the first place, so there's no such
	# race — deterministic, and still exercises the real async _do_spin()/_finish_spin() pipeline.
	var rs_scene: PackedScene = load("res://combat/combat.tscn")
	var rs_inst: Combat = rs_scene.instantiate()
	get_root().add_child(rs_inst)
	await process_frame
	await process_frame

	var rs_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var rs_enemy: Combatant = EnemyLibrary.make(&"rat")
	rs_inst._pcs = [rs_pc]
	rs_inst._enemies = [rs_enemy]
	rs_inst._dummies = []
	rs_inst._turn_manager.combatants = [rs_pc, rs_enemy]
	rs_inst._panels[rs_pc] = CombatantPanel.new()
	rs_inst._panels[rs_enemy] = CombatantPanel.new()
	rs_inst._attacker = rs_pc
	rs_inst._defender = rs_enemy
	rs_inst._plan = MainPhasePlan.new(rs_pc, rs_pc.ability_cost, 5, 2, null)
	rs_inst._plan.toggle_flee()
	_check(rs_inst._plan.flee_staged, "real-spin success: Flee staged via the real toggle_flee()")
	rs_inst._plan.commit()
	_check(rs_pc.flee_reel != null, "real-spin success: commit() built a real flee_reel on the combatant")
	# Pin the reel's faces to a single known SUCCESS face (established technique,
	# tests/test_darkness_rampage.gd) so the spin's outcome is deterministic.
	var success_face: ReelFace = null
	for f: ReelFace in rs_pc.flee_reel.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			success_face = f
			break
	rs_pc.flee_reel.faces = [success_face]
	rs_inst._prepare_strips(rs_pc.turn_reels)
	rs_inst._do_spin()  # the real spin-driving method — this is the exact call path that used to crash

	var rs_guard: int = 0
	while rs_inst._pending_strips > 0 and rs_guard < 2000:
		rs_guard += 1
		await process_frame
	_check(rs_inst._pending_strips <= 0, "real-spin success: the Flee spin's strip settled without hanging (no script error)")
	_check(rs_inst._fled_this_encounter, "real-spin success: a real SPIN with a forced SUCCESS flee tier actually fled")
	var rs_label: Label = rs_inst._overlay.get_node("ResultLabel")
	_check(rs_label.text == "FLED!", "real-spin success: result overlay reads FLED! (got: %s)" % rs_label.text)

	rs_inst.free()
	await process_frame

	# --- Real-spin FAILURE tier: the turn must end NORMALLY (no encounter-end, no hang), and Flee
	# must be stageable again on a later turn (staging state isn't left corrupted by a failed try). ---
	var rf_scene: PackedScene = load("res://combat/combat.tscn")
	var rf_inst: Combat = rf_scene.instantiate()
	get_root().add_child(rf_inst)
	await process_frame
	await process_frame

	var rf_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var rf_enemy: Combatant = EnemyLibrary.make(&"rat")
	rf_inst._pcs = [rf_pc]
	rf_inst._enemies = [rf_enemy]
	rf_inst._dummies = []
	rf_inst._turn_manager.combatants = [rf_pc, rf_enemy]
	rf_inst._panels[rf_pc] = CombatantPanel.new()
	rf_inst._panels[rf_enemy] = CombatantPanel.new()
	rf_inst._attacker = rf_pc
	rf_inst._defender = rf_enemy
	rf_inst._plan = MainPhasePlan.new(rf_pc, rf_pc.ability_cost, 5, 2, null)
	rf_inst._plan.toggle_flee()
	rf_inst._plan.commit()
	var fail_face: ReelFace = null
	for f: ReelFace in rf_pc.flee_reel.faces:
		if f.result_tier == ReelFace.ResultTier.FAILURE:
			fail_face = f
			break
	rf_pc.flee_reel.faces = [fail_face]
	rf_inst._prepare_strips(rf_pc.turn_reels)
	rf_inst._do_spin()

	var rf_guard: int = 0
	while rf_inst._pending_strips > 0 and rf_guard < 2000:
		rf_guard += 1
		await process_frame
	_check(rf_inst._pending_strips <= 0, "real-spin failure: the Flee spin's strip settled without hanging (no script error)")
	_check(not rf_inst._fled_this_encounter, "real-spin failure: a forced FAILURE flee tier does NOT end the encounter")
	_check(rf_inst._awaiting_end_turn, "real-spin failure: the turn ends normally (End Turn is reachable) instead of hanging")

	var rf_plan2: MainPhasePlan = MainPhasePlan.new(rf_pc, rf_pc.ability_cost, 5, 2, null)
	_check(rf_plan2.can_stage_flee(), "real-spin failure: Flee is stageable again on a later turn")

	rf_inst.free()
	await process_frame

	print(("COMBAT FLEE TEST PASSED" if _failures == 0 else "COMBAT FLEE TEST FAILED: %d" % _failures))
	quit(_failures)
