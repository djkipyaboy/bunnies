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

	print(("COMBAT FLEE TEST PASSED" if _failures == 0 else "COMBAT FLEE TEST FAILED: %d" % _failures))
	quit(_failures)
