extends SceneTree

# Headless end-to-end test: the single-NEUTRAL-face Jackpot Meter fill hook inside
# _apply_attack() (2026-07-29 UTIL-reel jackpot spec §2's "fill hooks"). Drives a real combat.tscn
# via the CombatHandoff entry point (mirrors tests/test_item_use_targeting_e2e.gd) and rigs one
# weapon reel to a forced-NEUTRAL landing that does NOT also complete a payline, isolating this
# hook from the payline hook (covered separately in test_jackpot_payline_fill_hook.gd, Task 3).
# Uses the Seer (2 reels) so reel-count math is simple and documented (CLAUDE.md class roster).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_fill_hooks.gd

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

	# Reel 0: forced to land on a NEUTRAL face that does NOT self-score a column payline — the
	# neighbors (top/bottom, via posmod adjacency) are SUCCESS, a different tier, so the 3-cell
	# column never all-matches. weights forces index 1 deterministically (Reel._select_index()).
	var reel0: ActionReel = pc.weapon.reels[0]
	reel0.faces = [_make_face(ReelFace.ResultTier.SUCCESS, 1.0), _make_face(ReelFace.ResultTier.NEUTRAL, 0.0), _make_face(ReelFace.ResultTier.SUCCESS, 1.0)]
	reel0.weights = [0.0, 1.0, 0.0]

	# Reel 1: a single SUCCESS face — self-scores a SUCCESS column (irrelevant to the jackpot) but
	# never a NEUTRAL one, so it can't contaminate this test's assertion.
	var reel1: ActionReel = pc.weapon.reels[1]
	reel1.faces = [_make_face(ReelFace.ResultTier.SUCCESS, 1.0)]
	reel1.weights = []

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	# NOTE (test-only fix, not production code): begin_encounter()'s enemy_ids param is a typed
	# Array[StringName]; an inline `[&"rat"]` literal is untyped and Godot rejects it at the call
	# boundary with a loud "Invalid type" error (the same class of typed-array gotcha this codebase
	# has hit before, just surfacing at a function call instead of a property assignment) — mirrors
	# every other e2e test's own `var enemy_ids: Array[StringName] = [...]` precedent (e.g.
	# tests/test_combat_amber.gd).
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"JackpotFillTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

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
	_check(inv.jackpot_meter == 0, "enemy-side NEUTRAL results (any prior turns) never contribute to the jackpot meter")

	inst._commit_main1()
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the spin's strips all settled within the frame guard")

	_check(inv.jackpot_meter == PartyInventory.JACKPOT_PER_UTIL_FACE, "one landed NEUTRAL face fills the jackpot meter by JACKPOT_PER_UTIL_FACE=%d (got %d)" % [PartyInventory.JACKPOT_PER_UTIL_FACE, inv.jackpot_meter])

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory exists, the hook must not crash ---
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
	_check(standalone._party_inventory == null, "standalone launches never capture a PartyInventory")
	standalone._enemies[0].take_damage(9999)
	_check(not standalone._enemies[0].is_alive(), "standalone combat still resolves normally (no crash from the null-guarded hook)")
	standalone.queue_free()
	await process_frame

	print(("JACKPOT FILL HOOKS TEST PASSED" if _failures == 0 else "JACKPOT FILL HOOKS TEST FAILED: %d" % _failures))
	quit(_failures)
