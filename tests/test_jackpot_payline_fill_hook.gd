extends SceneTree

# Headless end-to-end test: the UTIL-payline Jackpot Meter fill hook inside
# _on_paylines_resolved() (2026-07-29 UTIL-reel jackpot spec §2). Rigs BOTH of the Seer's 2 weapon
# reels to a single NEUTRAL face each — every PaylineLibrary.lines_for(2) line (2 columns + 3 rows
# = 5 lines; width 2 has no diagonals) scores NEUTRAL, so this also exercises the single-face hook
# (Task 2) twice (once per reel) on top of the 5 payline hits, deliberately proving the two hooks
# stack additively rather than one replacing the other.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_payline_fill_hook.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_face(tier: ReelFace.ResultTier, mult: float) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = mult
	return f

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	_check(pc.weapon.reels.size() == 2, "Seer has exactly 2 base weapon reels (got %d)" % pc.weapon.reels.size())

	for reel: ActionReel in pc.weapon.reels:
		reel.faces = [_make_face(ReelFace.ResultTier.NEUTRAL, 0.0)]
		reel.weights = []

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	# NOTE (test-only fix, not production code): begin_encounter()'s enemy_ids param is a typed
	# Array[StringName]; an inline `[&"rat"]` literal is untyped and Godot rejects it at the call
	# boundary with a loud "Invalid type" error when dispatched through a Node-typed handle (the
	# same class of typed-array gotcha this codebase has hit before, just surfacing at a function
	# call instead of a property assignment) — mirrors test_jackpot_fill_hooks.gd's own identical fix.
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"JackpotPaylineTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

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

	inst._commit_main1()
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the spin's strips all settled within the frame guard")

	# 2 reels each land NEUTRAL: 2 single-face fills (2*5=10) + a fully-NEUTRAL 2-wide grid scores
	# every one of PaylineLibrary.lines_for(2)'s 5 lines (2 columns + 3 rows, no diagonals at width 2)
	# as NEUTRAL paylines (5*15=75). Total 85 — comfortably under the 100 cap, so no clamping masks
	# the arithmetic.
	var expected: int = 2 * PartyInventory.JACKPOT_PER_UTIL_FACE + 5 * PartyInventory.JACKPOT_PER_UTIL_PAYLINE
	_check(inv.jackpot_meter == expected, "2 single-face fills + 5 scored NEUTRAL paylines stack additively (expected %d, got %d)" % [expected, inv.jackpot_meter])

	inst.queue_free()
	await process_frame

	print(("JACKPOT PAYLINE FILL HOOK TEST PASSED" if _failures == 0 else "JACKPOT PAYLINE FILL HOOK TEST FAILED: %d" % _failures))
	quit(_failures)
