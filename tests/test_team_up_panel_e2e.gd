extends SceneTree

# Headless end-to-end test: the real Team-Up! minigame UI, driven through a real combat.tscn via
# the CombatHandoff entry point (mirrors tests/test_item_use_targeting_e2e.gd). Rigs every reel's
# faces to a single deterministic symbol so the round's outcome is predictable, then drives the
# panel through a full round via its own button-press handlers (the same technique other e2e tests
# use for Tween-free, input-free driving). 2026-07-29 spec §3/§4.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_panel_e2e.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _face(symbol: StringName) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.team_up_symbol = symbol
	return f

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.jackpot_meter = PartyInventory.JACKPOT_CAP
	var vault: Vault = Vault.new()
	# NOTE (test-only fix, not production code): begin_encounter()'s enemy_ids param is a typed
	# Array[StringName]; an inline `[&"rat"]` literal is untyped and Godot rejects it at the call
	# boundary with a loud "Invalid type" error (documented gotcha, see tests/test_jackpot_fill_hooks.gd
	# and tests/test_team_up_trigger.gd's identical workaround).
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"TeamUpMinigameE2ETestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window")

	var enemy: Combatant = inst._enemies[0]
	var enemy_hp_before: int = enemy.hp

	inst._on_team_up_pressed()
	_check(inst._team_up_panel.visible, "Team-Up! opens the real minigame panel")
	_check(inst._team_up_panel._minigame is TeamUpMinigame, "open_for() built a real TeamUpMinigame from FreeSpinLibrary.make(&\"dungeon\")")

	# Rig every reel to a single deterministic "strike" face for a fully predictable tally.
	for reel: TeamUpReel in inst._team_up_panel._minigame.reels:
		reel.faces = [_face(&"strike")]

	for i: int in range(FreeSpinLibrary.MAX_SPINS):
		inst._team_up_panel._on_spin_pressed()

	_check(inst._team_up_panel._minigame.is_complete(), "the round completes after MAX_SPINS spins")
	_check(enemy.hp < enemy_hp_before, "an all-Strike round damages the enemy once resolved (%d -> %d)" % [enemy_hp_before, enemy.hp])
	_check(inst._team_up_panel._continue_button.visible, "Continue appears once the round resolves")

	inst._team_up_panel._continue_button.pressed.emit()
	_check(not inst._team_up_panel.visible, "Continue closes the panel")
	_check(inv.jackpot_meter == 0, "completing the real minigame still resets the Jackpot Meter (Plan 1's contract, unchanged)")
	_check(not inst._spin_button.disabled, "the triggering PC's own turn is still unaffected")

	# --- Click-to-lock wiring (fresh round on the same panel instance) ---
	inst._team_up_panel.open_for(FreeSpinLibrary.make(&"dungeon"), [pc], [enemy])
	for reel: TeamUpReel in inst._team_up_panel._minigame.reels:
		reel.faces = [_face(&"mend")]
	inst._team_up_panel._on_spin_pressed()
	inst._team_up_panel._on_cell_pressed(0, 0)
	_check(inst._team_up_panel._minigame.locked[0][0], "clicking a cell button calls lock() on that grid position")
	_check(inst._team_up_panel._cell_buttons[0][0].disabled, "a locked cell's button visually disables")

	inst.queue_free()
	await process_frame

	print(("TEAM UP PANEL E2E TEST PASSED" if _failures == 0 else "TEAM UP PANEL E2E TEST FAILED: %d" % _failures))
	quit(_failures)
