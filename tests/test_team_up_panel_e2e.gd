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

	_check(not inst._team_up_panel._resolve_lines.is_empty(), "the panel captured TeamUpEffects' per-effect report")
	inst._team_up_panel._continue_button.pressed.emit()
	_check(not inst._team_up_panel.visible, "Continue closes the panel")
	# The round's resolution must reach the player-visible combat log, not just the panel's own
	# tally label (final-review fix 2026-07-30).
	var log_text: String = inst._log_box.get_parsed_text()
	_check(log_text.contains("Team-Up STRIKE") and log_text.contains(enemy.display_name),
		"the Team-Up resolution is written to the combat log, naming the target")
	var handoff_lines: Array = CombatHandoff.event_log_entries
	var found_event: bool = false
	for entry: Dictionary in handoff_lines:
		if String(entry.get("line", "")).contains("Team-Up!"):
			found_event = true
	_check(found_event, "a Team-Up! summary also reaches the cross-scene event log")
	_check(inv.jackpot_meter == 0, "completing the real minigame still resets the Jackpot Meter (Plan 1's contract, unchanged)")
	_check(not inst._spin_button.disabled, "the triggering PC's own turn is still unaffected")

	# --- Click-to-lock wiring (fresh round on the same panel instance) ---
	inst._team_up_panel.open_for(FreeSpinLibrary.make(&"dungeon"), [pc], [enemy])
	for reel: TeamUpReel in inst._team_up_panel._minigame.reels:
		reel.faces = [_face(&"mend")]
	inst._team_up_panel._on_spin_pressed()
	# Emit the REAL button's `pressed` signal (not a direct _on_cell_pressed() call) on a
	# deliberately NON-[0][0] cell, so a per-cell closure that captured the wrong (or the last)
	# loop index can't accidentally still pass (final-review fix 2026-07-30).
	inst._team_up_panel._cell_buttons[2][1].pressed.emit()
	_check(inst._team_up_panel._minigame.locked[2][1], "pressing cell button [2][1] calls lock() on exactly that grid position")
	_check(not inst._team_up_panel._minigame.locked[0][0], "...and does NOT lock [0][0] (rules out 'every button locks the same cell')")
	_check(not inst._team_up_panel._minigame.locked[4][2], "...nor the last cell (rules out last-value closure capture)")
	_check(inst._team_up_panel._cell_buttons[2][1].disabled, "a locked cell's button visually disables")

	# --- 5-wide diagonals: an all-Surge grid completes EVERY payline lines_for(5) generates ---
	# (5 columns + 3 rows + 2 diagonals per 3-column window x 3 windows = 14). Nothing below width 3
	# has diagonals at all, so no other Team-Up test exercises them.
	var expected_lines: int = PaylineLibrary.lines_for(FreeSpinLibrary.COLS).size()
	_check(expected_lines == 14, "lines_for(5) really is 5 columns + 3 rows + 6 diagonals = 14 (got %d)" % expected_lines)
	inst._team_up_panel.open_for(FreeSpinLibrary.make(&"dungeon"), [pc], [enemy])
	_check(inst._team_up_panel._minigame.reels.size() == 5, "the authored dungeon config really is 5 reels wide")
	for reel: TeamUpReel in inst._team_up_panel._minigame.reels:
		reel.faces = [_face(&"surge")]
	for i: int in range(FreeSpinLibrary.MAX_SPINS):
		inst._team_up_panel._on_spin_pressed()
	var surge_tally: Dictionary = inst._team_up_panel._minigame.tally()
	_check(surge_tally["surge_lines"] == expected_lines,
		"an all-Surge 5x3 grid completes all %d paylines, diagonals included (got %d)" % [expected_lines, surge_tally["surge_lines"]])
	_check("\n".join(inst._team_up_panel._resolve_lines).contains("SURGE"), "a surge-only round still reports its amplification header")

	# --- Surge AMPLIFICATION over a real spun grid: column 0 all Surge (1 completed column line,
	# no row/diagonal can complete since cols 1-4 aren't Surge), columns 1-4 all Mend (12 faces).
	# Heal must read ceil(12 * MEND_PER_SYMBOL * (1 + 1*SURGE_AMPLIFY_PER_LINE)), not the raw base. ---
	inst._team_up_panel.open_for(FreeSpinLibrary.make(&"dungeon"), [pc], [enemy])
	var reels: Array[TeamUpReel] = inst._team_up_panel._minigame.reels
	reels[0].faces = [_face(&"surge")]
	for i: int in range(1, reels.size()):
		reels[i].faces = [_face(&"mend")]
	pc.take_damage(pc.hp - 10)
	_check(pc.hp == 10, "PC pre-damaged to 10 HP so the heal is fully observable (got %d)" % pc.hp)
	for i: int in range(FreeSpinLibrary.MAX_SPINS):
		inst._team_up_panel._on_spin_pressed()
	var mixed: Dictionary = inst._team_up_panel._minigame.tally()
	_check(mixed["surge_lines"] == 1, "exactly one Surge line completes (column 0 only) — got %d" % mixed["surge_lines"])
	_check(mixed["mend"] == 12, "12 Mend faces across columns 1-4 (got %d)" % mixed["mend"])
	var amp: float = 1.0 + 1.0 * TeamUpEffects.SURGE_AMPLIFY_PER_LINE
	var expected_heal: int = ceili(12 * TeamUpEffects.MEND_PER_SYMBOL * amp)
	_check(pc.hp == 10 + expected_heal,
		"the heal is Surge-amplified (expected %d -> hp %d, got %d)" % [expected_heal, 10 + expected_heal, pc.hp])
	_check(expected_heal > 12 * TeamUpEffects.MEND_PER_SYMBOL, "...and that really is MORE than the unamplified base")

	# --- Break's debuff badge must appear on the enemy panel IMMEDIATELY, not only once that enemy's
	# own turn comes around and refreshes its panel (final-review fix 2026-07-30). ---
	inst._team_up_panel.open_for(FreeSpinLibrary.make(&"dungeon"), [pc], [enemy])
	for reel: TeamUpReel in inst._team_up_panel._minigame.reels:
		reel.faces = [_face(&"break")]
	for i: int in range(FreeSpinLibrary.MAX_SPINS):
		inst._team_up_panel._on_spin_pressed()
	var enemy_panel: CombatantPanel = inst._panels[enemy]
	_check(enemy.has_effect(&"weakened"), "the all-Break round applied Weakened to the enemy")
	_check(not enemy_panel._status_label.text.contains("WEAKENED"), "the badge isn't on the panel yet (resolve alone doesn't refresh UI)")
	inst._team_up_panel._continue_button.pressed.emit()
	_check(enemy_panel._status_label.text.contains("WEAKENED"), "completing the round refreshes the enemy panel so the badge shows now")

	inst.queue_free()
	await process_frame

	print(("TEAM UP PANEL E2E TEST PASSED" if _failures == 0 else "TEAM UP PANEL E2E TEST FAILED: %d" % _failures))
	quit(_failures)
