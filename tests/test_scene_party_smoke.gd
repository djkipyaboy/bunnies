extends SceneTree

# Headless smoke test: a real N-vs-M party fight drives through the actual combat scene without script
# errors — 2 PCs (Warrior + Seer) vs 2 enemies (Rat + Ferret). Begins the round and pumps turns,
# auto-pressing SPIN/END/stun-gate so PC turns advance, while enemy turns auto-resolve. Catches wiring
# regressions in the refactored party paths (_build_combatants / columns / per-PC targeting / active-PC
# controls / placeholder enemy AI). Timing-independent assertions only (frame-driven combat may not
# finish within the guard).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_scene_party_smoke.gd

func _initialize() -> void:
	var failures: int = 0
	Combat._pc_class_ids = [&"warrior", &"seer"]
	Combat._enemy_ids = [&"rat", &"ferret"]
	Combat._dummies_enabled = false

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	inst._start_combat()   # BEGIN: build party + enemies, lay out columns, roll initiative, start round
	await process_frame

	if inst._panels.size() != 4:
		failures += 1; print("  FAIL: expected 4 panels, got %d" % inst._panels.size())
	else:
		print("  ok: 4 combatant panels laid out (2 party + 2 enemies)")
	if inst._turn_manager.round_number < 1:
		failures += 1; print("  FAIL: combat did not begin (round %d)" % inst._turn_manager.round_number)
	else:
		print("  ok: combat began (round %d)" % inst._turn_manager.round_number)

	# Drive turns: press SPIN / END / stun-gate whenever the scene waits on the player; enemy turns
	# auto-resolve on their own timers. Bounded by a frame guard (the fight may outlast it — that's fine).
	var guard: int = 0
	while is_instance_valid(inst) and not inst._turn_manager.is_combat_over() and guard < 800:
		guard += 1
		if inst._awaiting_stun_check:
			inst._on_spin_pressed()      # SPIN rolls the stun gate
		elif inst._awaiting_player_spin:
			inst._on_spin_pressed()      # commit Main-1 + spin
		elif inst._awaiting_end_turn:
			inst._on_end_turn_pressed()
		await process_frame

	# Per-PC targeting: each living PC has a remembered enemy target after taking turns (or none yet if
	# it hasn't acted) — assert any recorded target is a living-at-selection enemy, never a PC.
	var bad_target: bool = false
	for pc in inst._player_targets.keys():
		var tgt: Combatant = inst._player_targets[pc]
		if tgt != null and tgt.is_player:
			bad_target = true
	if bad_target:
		failures += 1; print("  FAIL: a PC's recorded target is a player")
	else:
		print("  ok: per-PC targets are enemies (none point at a PC)")

	if not is_instance_valid(inst):
		failures += 1; print("  FAIL: scene instance died mid-fight")
	else:
		print("  ok: scene survived %d driven frames (combat_over=%s)" % [guard, inst._turn_manager.is_combat_over()])

	print(("SCENE PARTY SMOKE TEST PASSED" if failures == 0 else "SCENE PARTY SMOKE TEST FAILED: %d" % failures))
	quit(failures)
