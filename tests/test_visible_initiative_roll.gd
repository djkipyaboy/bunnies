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

	await _run_real_button_press_scenario()

	print(("VISIBLE INITIATIVE ROLL TEST PASSED" if _failures == 0 else "VISIBLE INITIATIVE ROLL TEST FAILED: %d" % _failures))
	quit(_failures)

## Final-review Important #1 (2026-08-16): roll_initiative_for_test() previously re-implemented
## the roll->begin sequence by hand, so none of the tests calling it ever exercised the REAL
## button-press path — _on_roll_initiative_pressed(), the per-panel initiative_strips_settled
## aggregation, _on_panel_initiative_settled(), or _finish_initiative_roll() itself. This scenario
## drives that real path end to end instead: presses the actual button (which starts live Tween
## strip animations) and polls process_frame — the established idiom for waiting out a real
## Tween-based spin-and-settle sequence headlessly, see tests/test_item_use_targeting_e2e.gd's
## spin_guard loop — until the round has actually begun.
func _run_real_button_press_scenario() -> void:
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

	_check(inst._turn_manager.round_number == 0, "real button press: round_number is still 0 before pressing")
	_check(inst._roll_initiative_button.visible, "real button press: the Start Combat/Roll Initiative button is visible before pressing")

	inst._roll_initiative_button.pressed.emit()

	# Guard of 300 frames: this drives the REAL strip animations (Tween-based, per
	# InitiativeReelStrip.play_to()), not the roll_initiative_for_test() bypass, so it takes real
	# engine frames to settle rather than resolving on the next frame. 300 is generous headroom
	# over a single reel-strip settle (a couple hundred ms of animation at most) without risking a
	# true infinite hang if something regresses.
	var guard: int = 0
	while is_instance_valid(inst) and inst._turn_manager.round_number == 0 and guard < 300:
		guard += 1
		await process_frame
	_check(inst._turn_manager.round_number == 1, "real button press: round 1 actually began within the frame guard (got %d)" % inst._turn_manager.round_number)
	_check(not inst._roll_initiative_button.visible, "real button press: the button is hidden again once the round begins")
	_check(pc.current_initiative != 0, "real button press: PC current_initiative is set (got %d)" % pc.current_initiative)

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()
