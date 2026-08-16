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

	print(("COMBAT FLEE TEST PASSED" if _failures == 0 else "COMBAT FLEE TEST FAILED: %d" % _failures))
	quit(_failures)
