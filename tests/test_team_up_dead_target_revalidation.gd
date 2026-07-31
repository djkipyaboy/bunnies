extends SceneTree

# Headless end-to-end test: a Team-Up! round that KILLS the acting PC's remembered primary target
# must leave that PC aimed at a still-living enemy (final-review fix 2026-07-30).
#
# Why this needed its own coverage: Team-Up is the first mechanic in this codebase that can kill an
# enemy during the acting PC's OWN Main Phase 1 — every other kill happens during/after a spin, by
# which point _on_turn_started()'s identical dead-target handling has already run at the start of
# the next turn. Before the fix the PC was left targeting a corpse (whose panel had already hidden
# itself) and their subsequent weapon spin silently no-opped.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_dead_target_revalidation.gd

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
	# Two enemies, so the re-validation has somewhere real to re-aim (the typed-literal workaround
	# is the documented begin_encounter() gotcha, see tests/test_team_up_trigger.gd).
	var enemy_ids: Array[StringName] = [&"rat", &"ferret"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"TeamUpDeadTargetTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

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
	_check(inst._enemies.size() == 2, "the fight really has 2 enemies (got %d)" % inst._enemies.size())

	var target: Combatant = inst._defender
	_check(target != null and target.is_alive(), "the PC starts aimed at a living enemy")
	var other: Combatant = null
	for e: Combatant in inst._enemies:
		if e != target:
			other = e
	_check(other != null and other.is_alive(), "a second, different enemy is alive to re-aim at")

	# Rig a SMALL Strike tally: only column 0 is Strike (3 faces), the rest Mend. Enough to finish
	# off a 1-HP target, nowhere near enough to also kill the healthy second enemy.
	target.take_damage(target.hp - 1)
	_check(target.hp == 1, "target pre-damaged to 1 HP (got %d)" % target.hp)

	inst._on_team_up_pressed()
	_check(inst._team_up_panel.visible, "the Team-Up! panel opened")
	var reels: Array[TeamUpReel] = inst._team_up_panel._minigame.reels
	reels[0].faces = [_face(&"strike")]
	for i: int in range(1, reels.size()):
		reels[i].faces = [_face(&"mend")]
	for i: int in range(FreeSpinLibrary.MAX_SPINS):
		inst._team_up_panel._on_spin_pressed()

	_check(not target.is_alive(), "the Team-Up round killed the PC's primary target")
	_check(other.is_alive(), "the OTHER enemy survived the same round (hp %d)" % other.hp)

	inst._team_up_panel._continue_button.pressed.emit()
	_check(inst._defender == other, "_defender was re-validated onto the surviving enemy")
	_check(inst._player_targets[pc] == other, "the PC's remembered target was updated too, not just _defender")
	_check(inst._awaiting_player_spin, "the PC's own Main Phase 1 is still open")

	# --- No living enemies at all: first_living() returns null, which must clear the outlines
	# without crashing (mirrors _on_turn_started's identical null case). ---
	other.take_damage(9999)
	_check(not other.is_alive(), "the last enemy is dead before the null-case check")
	var no_lines: Array[String] = []
	inst._on_team_up_completed(no_lines)
	_check(inst._defender == null, "_defender clears to null when nothing is left alive, no crash")

	inst.queue_free()
	await process_frame

	print(("TEAM UP DEAD TARGET REVALIDATION TEST PASSED" if _failures == 0 else "TEAM UP DEAD TARGET REVALIDATION TEST FAILED: %d" % _failures))
	quit(_failures)
