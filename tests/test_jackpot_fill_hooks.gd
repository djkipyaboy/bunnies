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

## Rigs [param reel]'s faces so it lands NEUTRAL 100% of the time via a deterministic weighted
## index (Reel._select_index()), WITHOUT that NEUTRAL also completing a column payline: the two
## posmod-wrapped neighbors (top/bottom of the 3-cell column) are a different tier (SUCCESS), so the
## column can never all-match on NEUTRAL. Shared by every rig in this file (PC/enemy/standalone) so
# all three read identically and can be reviewed as one technique.
func _rig_neutral_reel(reel: ActionReel) -> void:
	reel.faces = [_make_face(ReelFace.ResultTier.SUCCESS, 1.0), _make_face(ReelFace.ResultTier.NEUTRAL, 0.0), _make_face(ReelFace.ResultTier.SUCCESS, 1.0)]
	reel.weights = [0.0, 1.0, 0.0]

## Rigs [param reel] to a single SUCCESS face — self-scores a SUCCESS column (irrelevant to the
## jackpot) but can never land NEUTRAL, so it can't contaminate a NEUTRAL-only assertion.
func _rig_success_only_reel(reel: ActionReel) -> void:
	reel.faces = [_make_face(ReelFace.ResultTier.SUCCESS, 1.0)]
	reel.weights = []

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	_check(pc.weapon.reels.size() == 2, "Seer has exactly 2 base weapon reels (got %d)" % pc.weapon.reels.size())
	_rig_neutral_reel(pc.weapon.reels[0])
	_rig_success_only_reel(pc.weapon.reels[1])

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

	# Rig the enemy's (rat's) weapon reels to the identical forced-NEUTRAL technique, so the
	# "enemy-side NEUTRAL never contributes" assertion below is deterministically meaningful on
	# every run, not a trivial 0==0 that only holds because the enemy hasn't acted yet.
	_check(inst._enemies.size() == 1, "exactly one enemy (the rat) is in this fight")
	var enemy: Combatant = inst._enemies[0]
	_check(enemy.weapon.reels.size() == 2, "the rat has exactly 2 base weapon reels (got %d)" % enemy.weapon.reels.size())
	_rig_neutral_reel(enemy.weapon.reels[0])
	_rig_success_only_reel(enemy.weapon.reels[1])

	# Turn order between the PC and the rat is decided by a real, random d100 Initiative roll
	# (DESIGN.md §4.1/§4.2) that has ALREADY happened synchronously inside combat.tscn's _ready(),
	# before this script regains control — empirically confirmed roughly 50/50 across repeated runs,
	# not something this test can force deterministically from outside without either touching
	# production code or risking an unrelated STUNNED side effect (current_initiative < -20) from a
	# heavy-handed Finesse hack. Rather than assume an order, branch on whichever combatant's turn
	# actually started first; both branches drive the same real spins and prove the same two facts
	# (the enemy's NEUTRAL never fills the meter; the PC's NEUTRAL fills it by exactly one
	# increment) — just checked in whichever order reality gives us this run.
	var enemy_went_first: bool = inst._attacker == enemy

	if enemy_went_first:
		# The enemy's turn is already under way (its real spin fires off a Timer, DESIGN.md-accurate
		# "AI thinks" delay — see ENEMY_THINK_DELAY) — wait through it for real; its rigged NEUTRAL
		# face lands here, resolving before we ever reach the PC's own pre-spin window.
		var guard: int = 0
		while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
			guard += 1
			await process_frame
		_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window (the rat acted first)")
		_check(inv.jackpot_meter == 0, "the rat's already-resolved rigged-NEUTRAL spin did not add to the jackpot meter")
	else:
		_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window (the PC acted first)")
		_check(inv.jackpot_meter == 0, "nothing has spun yet, so the jackpot meter is still at its initial 0")

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

	if not enemy_went_first:
		# The rat hasn't acted yet in this run's ordering. A PC's own turn is gated behind TWO
		# stops, not one: _awaiting_player_spin (Main 1, cleared above by _commit_main1()+_do_spin())
		# THEN _awaiting_end_turn (a post-spin review pause — combat.gd only auto-advances an ENEMY's
		# turn via resume_after_combat(); a PLAYER's turn waits for an explicit End Turn press, see
		# combat.gd's _finish_spin()/_on_end_turn_pressed()). Without pressing it here, the round can
		# never advance and the rat never gets its turn — confirmed empirically: widening the old
		# guard2 to 5000 frames didn't help, because it wasn't a timing problem, it was a genuinely
		# stuck turn (same two-gate shape documented in tests/test_item_use_targeting_e2e.gd).
		inst._on_end_turn_pressed()
		# Wait through the rat's real turn now (the same rigged NEUTRAL reel) and confirm the meter
		# still doesn't move, proving the exclusion from this ordering too. Round 1 holds exactly one
		# turn per combatant (no dummies enabled), so round_number reaching 2 is a solid,
		# order-agnostic signal that the rat's own turn resolved.
		var guard2: int = 0
		while is_instance_valid(inst) and inst._turn_manager.round_number < 2 and guard2 < 1000:
			guard2 += 1
			await process_frame
		_check(inst._turn_manager.round_number >= 2, "round 2 started, meaning the rat's own turn has now resolved too")
		_check(inv.jackpot_meter == PartyInventory.JACKPOT_PER_UTIL_FACE, "the rat's rigged-NEUTRAL spin (going second) still did not add to the jackpot meter (stayed at %d)" % PartyInventory.JACKPOT_PER_UTIL_FACE)

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory exists, the hook must not crash under a real spin ---
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

	# Drive one real PC-side reel spin to a forced-NEUTRAL result here too — not just take_damage()
	# below — so the hook's `_attacker.is_player and _party_inventory != null and ...` condition is
	# actually evaluated against a live NEUTRAL attack.face with a null _party_inventory, proving the
	# guard is safe under a real spin, not merely that combat starts and take_damage() works.
	var standalone_pc: Combatant = standalone._pcs[0]
	_check(standalone_pc.weapon.reels.size() == 3, "the standalone Warrior has exactly 3 base weapon reels (got %d)" % standalone_pc.weapon.reels.size())
	_rig_neutral_reel(standalone_pc.weapon.reels[0])
	for i: int in range(1, standalone_pc.weapon.reels.size()):
		_rig_success_only_reel(standalone_pc.weapon.reels[i])

	# Turn order is random here too (see above) — the standalone check doesn't need to isolate who
	# goes first, only that the PC's own spin genuinely happens; wait through the rat's turn if it
	# goes first, exactly like the handoff scenario's guard loop.
	var sguard: int = 0
	while is_instance_valid(standalone) and not (standalone._awaiting_player_spin and standalone._attacker == standalone_pc) and sguard < 1000:
		sguard += 1
		await process_frame
	_check(standalone._awaiting_player_spin and standalone._attacker == standalone_pc, "standalone reached the PC's own pre-spin window")

	standalone._commit_main1()
	standalone._prepare_strips(standalone_pc.turn_reels)
	standalone._phase_manager.proceed_to_combat()
	standalone._do_spin()

	var sspin_guard: int = 0
	while standalone._pending_strips > 0 and sspin_guard < 2000:
		sspin_guard += 1
		await process_frame
	_check(standalone._pending_strips <= 0, "standalone spin's strips all settled within the frame guard")
	_check(standalone._party_inventory == null, "standalone _party_inventory stayed null all the way through a real NEUTRAL-face spin (no crash from the null-guarded hook)")

	standalone._enemies[0].take_damage(9999)
	_check(not standalone._enemies[0].is_alive(), "standalone combat still resolves normally after the spin (no crash from the null-guarded hook)")
	standalone.queue_free()
	await process_frame

	print(("JACKPOT FILL HOOKS TEST PASSED" if _failures == 0 else "JACKPOT FILL HOOKS TEST FAILED: %d" % _failures))
	quit(_failures)
