extends SceneTree

# Headless test: pressing Continue on a WIN applies post-combat recovery to every PC and appends a
# summary to the result label (2026-08-13 post-combat-flow spec §3). Mirrors
# tests/test_combat_handoff_entry.gd's exact handoff-harness pattern.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_win_recovery.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# --- WIN case: PC damaged + meter partially charged before Continue is pressed ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.hp = pc.max_hp - 50  # damaged, so recovery is actually observable
	pc.bonus_meter.value = pc.bonus_meter.floor + 2  # above floor, below cap -> resolve_post_combat drops it to floor
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
	var meter_floor: int = pc.bonus_meter.floor
	inst._last_result_won = true
	inst.press_continue_for_test()

	_check(pc.hp > hp_before, "WIN + Continue recovered some HP (before %d, after %d)" % [hp_before, pc.hp])
	_check(pc.bonus_meter.value == meter_floor, "WIN + Continue resolved the Bonus Meter to its floor (got %d, floor %d)" % [pc.bonus_meter.value, meter_floor])

	var label: Label = inst._overlay.get_node("ResultLabel")
	_check(label.text.contains("HP"), "result label mentions the HP recovery (got: %s)" % label.text)

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- LOSS case (regression): recovery must NOT apply on a loss — that's the defeat-handling plan's job ---
	var loss_pc: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	loss_pc.hp = loss_pc.max_hp - 50
	CombatHandoff.begin_encounter(loss_pc, [], inv, vault, enemy_ids, &"OverworldFerret", return_path, Vector2(1.0, 2.0))

	var loss_scene: PackedScene = load("res://combat/combat.tscn")
	var loss_inst: Combat = loss_scene.instantiate()
	get_root().add_child(loss_inst)
	await process_frame
	await process_frame

	var loss_hp_before: int = loss_pc.hp
	loss_inst._last_result_won = false
	loss_inst.press_continue_for_test()
	_check(loss_pc.hp == loss_hp_before, "LOSS + Continue does NOT apply win-side recovery (hp unchanged, got %d, was %d)" % [loss_pc.hp, loss_hp_before])

	loss_inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- RE-ENTRANCY (final-review Important finding, 2026-08-13): a second Continue press while
	# the first is still "in flight" must be a total no-op, not a double-application. Since
	# press_continue_for_test() calls the same shared _resolve_handoff_continue() the real button
	# handler awaits on, calling it twice back-to-back here exercises the actual guard the button
	# handler relies on (the guard lives in the shared resolver, not only in the async button
	# handler, precisely so it's headlessly testable this way).
	var reentrant_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	reentrant_pc.hp = reentrant_pc.max_hp - 50
	reentrant_pc.bonus_meter.value = reentrant_pc.bonus_meter.floor + 2
	CombatHandoff.begin_encounter(reentrant_pc, [], inv, vault, enemy_ids, &"OverworldRat", return_path, Vector2(1.0, 2.0))

	var re_scene: PackedScene = load("res://combat/combat.tscn")
	var re_inst: Combat = re_scene.instantiate()
	get_root().add_child(re_inst)
	await process_frame
	await process_frame

	var re_hp_before: int = reentrant_pc.hp
	var re_meter_floor: int = reentrant_pc.bonus_meter.floor
	re_inst._last_result_won = true
	var first_path: String = re_inst.press_continue_for_test()
	var hp_after_first: int = reentrant_pc.hp
	var label_after_first: String = (re_inst._overlay.get_node("ResultLabel") as Label).text

	var second_path: String = re_inst.press_continue_for_test()
	_check(second_path == "", "second press_continue_for_test() call returns an empty path (no-op), got: %s" % second_path)
	_check(first_path == return_path, "first call still returned the real return path (got: %s)" % first_path)
	_check(reentrant_pc.hp == hp_after_first, "second Continue press did NOT apply a second dose of HP recovery (before 2nd press %d, after %d)" % [hp_after_first, reentrant_pc.hp])
	_check(reentrant_pc.bonus_meter.value == re_meter_floor, "second Continue press did NOT re-resolve the Bonus Meter (still at floor %d, got %d)" % [re_meter_floor, reentrant_pc.bonus_meter.value])
	var label_after_second: String = (re_inst._overlay.get_node("ResultLabel") as Label).text
	_check(label_after_second == label_after_first, "second Continue press did NOT append a duplicate recovery line to the result label")
	_check(re_hp_before < hp_after_first, "sanity: the first press actually did apply real recovery (before %d, after 1st %d)" % [re_hp_before, hp_after_first])

	re_inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	# --- DOWNED-PC BONUS METER (final-review Important finding, 2026-08-13): a PC who was KO'd
	# during the winning fight must still have resolve_post_combat() called on their meter — only
	# their HP/Stamina/Mana recovery and the label line are correctly skipped while dead.
	var alive_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	alive_pc.hp = alive_pc.max_hp - 50
	var downed_pc: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	downed_pc.hp = 0
	downed_pc.bonus_meter.value = downed_pc.bonus_meter.floor + 2  # above floor, below cap -> resolve_post_combat drops it to floor
	CombatHandoff.begin_encounter(alive_pc, [downed_pc], inv, vault, enemy_ids, &"OverworldRat", return_path, Vector2(1.0, 2.0))

	var downed_scene: PackedScene = load("res://combat/combat.tscn")
	var downed_inst: Combat = downed_scene.instantiate()
	get_root().add_child(downed_inst)
	await process_frame
	await process_frame

	var downed_meter_floor: int = downed_pc.bonus_meter.floor
	_check(not downed_pc.is_alive(), "sanity: the downed PC is actually dead (hp %d)" % downed_pc.hp)
	downed_inst._last_result_won = true
	downed_inst.press_continue_for_test()
	_check(downed_pc.bonus_meter.value == downed_meter_floor, "downed PC's Bonus Meter still resolved to its floor despite being dead (got %d, floor %d)" % [downed_pc.bonus_meter.value, downed_meter_floor])

	var downed_label: Label = downed_inst._overlay.get_node("ResultLabel")
	_check(not downed_label.text.contains(downed_pc.display_name), "downed PC gets no HP/Stamina/Mana recovery label line (label: %s)" % downed_label.text)

	downed_inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("COMBAT WIN RECOVERY TEST PASSED" if _failures == 0 else "COMBAT WIN RECOVERY TEST FAILED: %d" % _failures))
	quit(_failures)
