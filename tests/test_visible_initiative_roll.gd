extends SceneTree

# Headless test: the encounter-start sequence is gated behind roll_initiative_for_test() (real
# button press in production; this hook bypasses only the animation, not the logic) and correctly
# populates the turn order / begins the round (2026-08-16 visible-initiative-reels spec §2). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_visible_initiative_roll.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"OverworldRat", "res://world/overworld_demo.tscn", Vector2(1.0, 2.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	# Before rolling: current_initiative is still whatever the fresh Combatant defaults to (0 for
	# an unrolled PC) — the tracker/turn order genuinely hasn't been decided yet.
	_check(pc.current_initiative == 0, "before rolling: PC current_initiative is still 0 (unrolled)")
	_check(inst._turn_manager.round_number == 0, "before rolling: round_number is still 0 (fight hasn't begun)")

	inst.roll_initiative_for_test()
	await process_frame

	_check(pc.current_initiative != 0, "after rolling: PC current_initiative is set (got %d)" % pc.current_initiative)
	_check(inst._turn_manager.round_number == 1, "after rolling: round 1 has begun (got %d)" % inst._turn_manager.round_number)

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("VISIBLE INITIATIVE ROLL TEST PASSED" if _failures == 0 else "VISIBLE INITIATIVE ROLL TEST FAILED: %d" % _failures))
	quit(_failures)
