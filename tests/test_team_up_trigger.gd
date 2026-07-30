extends SceneTree

# Headless end-to-end test: the "Team-Up!" trigger button (2026-07-29 UTIL-reel jackpot spec §3):
# disabled below JACKPOT_CAP, enabled at cap during the PC's own Main Phase 1, pressing it is a
# FREE action (doesn't touch MainPhasePlan's staged state or consume the turn), and completing the
# (placeholder, this plan) TeamUpPanel resets the meter to 0 and hands control back to the same
# still-open Main Phase 1.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_trigger.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.jackpot_meter = 50  # below cap
	var vault: Vault = Vault.new()
	# NOTE (test-only fix, not production code): begin_encounter()'s enemy_ids param is a typed
	# Array[StringName]; an inline `[&"rat"]` literal is untyped and Godot rejects it at the call
	# boundary with a loud "Invalid type" error (documented gotcha, see tests/test_jackpot_fill_hooks.gd).
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"TeamUpTriggerTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

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

	_check(inst._team_up_button.disabled, "Team-Up! stays disabled below the cap (meter=50)")

	inv.jackpot_meter = PartyInventory.JACKPOT_CAP
	inst._refresh_main1_preview()
	_check(not inst._team_up_button.disabled, "Team-Up! becomes enabled once the meter hits the cap")

	var staged_before: String = inst._staged_state_key()
	# Emit the button's own `pressed` signal (not a direct _on_team_up_pressed() call) so the
	# _bind_signals() wiring itself (_team_up_button.pressed.connect(_on_team_up_pressed)) is
	# actually exercised — final-review fix 2026-07-30: every prior assertion in this file called
	# the handler directly, so the connection itself was never proven to work.
	inst._team_up_button.pressed.emit()
	_check(inst._team_up_panel.visible, "pressing Team-Up! (via its own pressed signal) opens the full-screen panel")
	_check(inst._staged_state_key() == staged_before, "pressing Team-Up! doesn't stage anything in MainPhasePlan (free action)")
	_check(inst._spin_button.disabled, "the normal SPIN button is paused while the panel is open")

	inst._team_up_panel._continue_button.pressed.emit()
	_check(not inst._team_up_panel.visible, "Continue closes the panel")
	_check(inv.jackpot_meter == 0, "completing Team-Up! resets the meter to 0")
	_check(not inst._spin_button.disabled, "the triggering PC's own turn is unaffected — SPIN is available again")
	_check(inst._team_up_button.disabled, "Team-Up! goes back to disabled now that the meter is 0")
	_check(inst._awaiting_player_spin and inst._attacker == pc, "control returns to the SAME still-open Main Phase 1")

	_check(inst._jackpot_bar is ProgressBar, "combat.gd builds a _jackpot_bar")

	# --- Guard clause: the handler must no-op outside the PC's own Main Phase 1 (2026-07-30
	# final-review gap) — e.g. during the post-spin "review, then END TURN" window, or an enemy's
	# turn — even if the meter happens to be sitting at the cap.
	inv.jackpot_meter = PartyInventory.JACKPOT_CAP
	inst._awaiting_player_spin = false
	inst._on_team_up_pressed()
	_check(not inst._team_up_panel.visible, "the handler no-ops when _awaiting_player_spin is false, even at a full meter")
	_check(inv.jackpot_meter == PartyInventory.JACKPOT_CAP, "the meter is untouched by a no-op press")

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory, the button must stay disabled and not crash ---
	CombatHandoff.clear_pending()
	Combat._pc_class_ids = [&"warrior"]
	Combat._enemy_ids = [&"rat"]
	Combat._dummies_enabled = false
	Combat._endgame_enabled = false
	var standalone_scene: PackedScene = load("res://combat/combat.tscn")
	var standalone: Combat = standalone_scene.instantiate()
	get_root().add_child(standalone)
	await process_frame
	standalone._start_combat()
	await process_frame
	_check(standalone._team_up_button.disabled, "standalone launches (_party_inventory == null) keep Team-Up! disabled")
	standalone.queue_free()
	await process_frame

	print(("TEAM UP TRIGGER TEST PASSED" if _failures == 0 else "TEAM UP TRIGGER TEST FAILED: %d" % _failures))
	quit(_failures)
