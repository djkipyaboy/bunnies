extends SceneTree

# Headless test: combat.gd's overworld->combat handoff entry point
# (spec 2026-07-11-overworld-combat-handoff-design.md §3.4/§3.5, plan Task C).
#
# CombatHandoff is registered as an autoload, but a bare `extends SceneTree` test script does NOT
# get the same autoload injection a real running scene gets — reference it via
# get_root().get_node("CombatHandoff") (confirmed pattern, see tests/test_combat_handoff.gd).
# combat.gd itself (a real scene script) CAN reference the bare `CombatHandoff` identifier directly.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_entry.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()  # defensive: don't let an earlier section's state bleed in

	# -----------------------------------------------------------------------
	# Regression (most important): CombatHandoff.pc == null -> standalone flow completely unaffected.
	# -----------------------------------------------------------------------
	Combat._pc_class_ids = [&"warrior"]
	Combat._enemy_ids = [&"rat"]
	Combat._dummies_enabled = false
	Combat._endgame_enabled = false

	var scene: PackedScene = load("res://combat/combat.tscn")
	var standalone: Combat = scene.instantiate()
	get_root().add_child(standalone)
	await process_frame
	await process_frame

	_check(standalone._start_overlay != null, "standalone launch (pc==null) still builds the start overlay")
	_check(standalone._arrived_via_handoff == false, "standalone launch does not set _arrived_via_handoff")
	_check(standalone._turn_manager.round_number == 0, "standalone launch does NOT auto-start combat (round still 0)")

	var standalone_has_restart_button: bool = false
	for child: Node in standalone._overlay.get_children():
		if child is Button and (child as Button).text == "Fight again (re-pick rosters)":
			standalone_has_restart_button = true
	_check(standalone_has_restart_button, "standalone launch's result card still contains the 'Fight again' button")

	standalone.queue_free()
	await process_frame

	# -----------------------------------------------------------------------
	# Handoff entry: CombatHandoff.pc populated BEFORE the scene loads -> skip the overlay, build the
	# fight straight from the handoff's real Combatants.
	# -----------------------------------------------------------------------
	var handoff_pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var handoff_companion: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	var encounter_id: StringName = &"OverworldRat"
	var return_path: String = "res://world/overworld_demo.tscn"
	var return_pos: Vector2 = Vector2(111.0, 222.0)

	CombatHandoff.begin_encounter(handoff_pc, [handoff_companion], inv, vault, enemy_ids,
		encounter_id, return_path, return_pos)

	var handoff_scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = handoff_scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._arrived_via_handoff == true, "handoff launch sets _arrived_via_handoff")
	_check(inst._start_overlay == null, "handoff launch never builds the start overlay")
	_check(inst._pcs.size() == 2, "handoff launch builds _pcs from CombatHandoff.pc + companions (2 total)")
	_check(not inst._pcs.is_empty() and inst._pcs[0] == handoff_pc, "_pcs[0] is the EXACT CombatHandoff.pc reference, not a fresh build")
	_check(inst._pcs.size() > 1 and inst._pcs[1] == handoff_companion, "_pcs[1] is the exact companion reference")
	_check(inst._enemies.size() == 1 and inst._enemies[0].display_name == EnemyLibrary.make(&"rat").display_name,
		"_enemies built from CombatHandoff.enemy_ids via the existing EnemyLibrary loop")
	_check(inst._turn_manager.round_number >= 1, "handoff launch auto-starts combat (round rolled)")

	# Regression (playtest-found, 2026-07-12): _build_overlay() reads _arrived_via_handoff to decide
	# which result-card button to build, but it used to run (via _build_ui()) BEFORE the handoff
	# check set that flag — so the overlay ALWAYS got "Fight again", even on a real handoff launch,
	# despite _arrived_via_handoff correctly reading true by the time _ready() finished. Checking the
	# flag's final value (as the assertion above does) missed this; only inspecting what button was
	# actually BUILT catches it.
	var found_continue_button: bool = false
	var found_restart_button: bool = false
	for child: Node in inst._overlay.get_children():
		if child is Button:
			if (child as Button).text == "Continue":
				found_continue_button = true
			elif (child as Button).text == "Fight again (re-pick rosters)":
				found_restart_button = true
	_check(found_continue_button, "handoff launch's result card actually contains a 'Continue' button")
	_check(not found_restart_button, "handoff launch's result card does NOT contain the standalone 'Fight again' button")

	# -----------------------------------------------------------------------
	# WIN via "Continue": mark_defeated fires, pending fields clear, defeated id persists.
	# -----------------------------------------------------------------------
	inst._last_result_won = true
	var returned_path_win: String = inst.press_continue_for_test()

	_check(CombatHandoff.is_defeated(&"OverworldRat") == true, "WIN + Continue marks the encounter defeated")
	_check(CombatHandoff.pc == null, "WIN + Continue clears the pending handoff pc")
	_check(CombatHandoff.pending_encounter_id == &"", "WIN + Continue clears pending_encounter_id")
	_check(returned_path_win == return_path, "WIN + Continue returns the correct scene path for the scene change")

	inst.queue_free()
	await process_frame

	# -----------------------------------------------------------------------
	# LOSS via "Continue": mark_defeated does NOT fire, but pending fields still clear and the
	# scene-change path is still correctly reported.
	# -----------------------------------------------------------------------
	CombatHandoff.clear_pending()  # start this section clean
	var loss_pc: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	CombatHandoff.begin_encounter(loss_pc, [], inv, vault, enemy_ids,
		&"OverworldFerret", return_path, return_pos)

	var loss_scene: PackedScene = load("res://combat/combat.tscn")
	var loss_inst: Combat = loss_scene.instantiate()
	get_root().add_child(loss_inst)
	await process_frame
	await process_frame

	loss_inst._last_result_won = false
	var returned_path_loss: String = loss_inst.press_continue_for_test()

	_check(CombatHandoff.is_defeated(&"OverworldFerret") == false, "LOSS + Continue does NOT mark the encounter defeated")
	_check(CombatHandoff.pc == null, "LOSS + Continue still clears the pending handoff pc")
	_check(returned_path_loss == return_path, "LOSS + Continue still returns the correct scene path (scene change still happens)")

	loss_inst.queue_free()
	await process_frame

	print(("COMBAT HANDOFF ENTRY TEST PASSED" if _failures == 0 else "COMBAT HANDOFF ENTRY TEST FAILED: %d" % _failures))
	quit(_failures)
