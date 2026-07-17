extends SceneTree

# Headless end-to-end test: the full combat item-use targeting + item reel path (2026-07-16 design
# §5's last bullet). Drives the real combat.tscn scene via the CombatHandoff entry point (mirrors
# tests/test_combat_xp.gd), stages a Healing Potion, retargets to a companion, and rigs the item-use
# reel's faces to a known tier before calling the orchestrator's spin methods directly — the
# established technique for forcing a deterministic outcome from a probabilistic reel (see
# tests/test_jinxed_reels.gd: Reel.spin() picks a random index into .faces, so a 1-element faces
# array always resolves to that one face).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_targeting_e2e.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_face(tier: ReelFace.ResultTier) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = 0.0
	return f

func _run_scenario(rig_tier: ReelFace.ResultTier, expect_crit: bool) -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var companion: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	companion.take_damage(companion.max_hp - 10)  # leave the companion damaged so the heal is observable
	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 20
	potion.quantity = 1
	inv.items = [potion]
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [companion], inv, vault, enemy_ids,
		&"ItemUseE2ETestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	# Guard of 1000, not the brief's 400: debugged live with a standalone repro script printing
	# _attacker/_awaiting_player_spin every 20 frames across 45 runs. With only 3 combatants (pc,
	# companion, rat) the PC's turn arrives after 0, 1, or 2 other full turns depending on the random
	# initiative roll, clustering at guard ~0 / ~200-270 / ~470-492 respectively — each other combatant's
	# full turn (ENEMY_THINK_DELAY's real 0.6s wait, or the companion's own spin-and-settle Tween
	# animation this loop now drives, SPIN_DURATION 1.15s + per-reel STRIP_STAGGER) costs a few hundred
	# frames of real headless engine time, not react-immediately logic. 400 sits inside the worst (2-turns-
	# first) cluster's range and reliably failed whenever the PC went last (~25-40% of file runs, since
	# this file rolls initiative twice, once per scenario). 1000 is >2x the observed max (492) across all
	# 45 debug runs, none of which needed more than 492.
	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		# Let the companion pass its own turn if it goes first. A player-side turn passes through TWO
		# gated states before the turn manager moves on: _awaiting_player_spin (Main 1 — needs an actual
		# spin) then _awaiting_end_turn (post-spin review — needs End Turn). Debugged live: calling only
		# _on_end_turn_pressed() while _awaiting_player_spin is true is a no-op (that handler guards on
		# _awaiting_end_turn, not _awaiting_player_spin), so the companion's turn never advanced — found
		# via a standalone repro script that printed _attacker/_awaiting_player_spin/_awaiting_end_turn
		# every 20 frames.
		if inst._awaiting_player_spin and inst._attacker != null and inst._attacker.is_player and inst._attacker != pc:
			inst._on_spin_pressed()
		elif inst._awaiting_end_turn and inst._attacker != null and inst._attacker.is_player and inst._attacker != pc:
			inst._on_end_turn_pressed()
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window")

	var pc_hp_before: int = pc.hp

	# Stage the Healing Potion (mirrors _on_item_menu_item_pressed's model call).
	inst._plan.toggle_item(&"healing_potion")
	_check(inst._plan.staged_item_type == &"healing_potion", "the potion is staged")

	# Retarget to the companion (mirrors clicking the companion's ally-target click-catcher).
	inst._select_ally_target(companion)
	_check(inst._ally_target == companion, "retargeted to the companion")

	# Commit Main 1 directly (same call _on_spin_pressed makes) — this appends the item-use reel and
	# sets item_use_reel/pending_item_base_heal.
	inst._commit_main1()
	_check(pc.item_use_reel != null, "commit appended the item-use reel")
	_check(pc.pending_item_base_heal == 20, "commit recorded the base heal amount")

	# Rig the item-use reel to a single known-tier face — deterministic outcome (see file header).
	pc.item_use_reel.faces = [_make_face(rig_tier)]

	# Drive the rest of the spin the same way _on_spin_pressed does after _commit_main1(): rebuild the
	# strips from the committed reels, enter Combat, and resolve.
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	# _do_spin() only STARTS the spin: each ReelStrip animates to its landed face via a real Tween
	# (SPIN_DURATION 1.15s + STRIP_STAGGER 0.25s per reel index), and only strip_settled -> _apply_attack
	# -> _finish_spin (where the heal actually lands) once every strip has settled. Debugged live: without
	# this wait, companion.hp read the PRE-heal value every time (_do_spin returns long before the tweens
	# finish) — poll the same _pending_strips counter _apply_attack decrements, mirroring the turn-wait
	# loop above rather than a fixed sleep.
	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the spin's strips all settled within the frame guard")

	# Playtest-found gap (2026-07-16): the item reel used to log through the same generic
	# "<name> reel -> <tier> (no damage) vs <enemy>" line every other no-damage utility reel uses,
	# which reads as an attack against the enemy and never identifies it as the item reel at all —
	# a player couldn't tell which of the several reels shown was the potion's own spin.
	# _log() appends via RichTextLabel.add_text(), which does NOT update the .text property (that only
	# reflects content assigned directly to .text) — get_parsed_text() is what actually returns the
	# accumulated rendered content regardless of how it was added.
	var log_text: String = inst._log_box.get_parsed_text()
	_check(log_text.find("Item Reel") != -1, "the combat log identifies the item reel's own line distinctly (log tail: '%s')" % log_text.substr(maxi(0, log_text.length() - 300)))

	var expected_amount: int = ceili(20.0 * (1.5 if expect_crit else 1.0))
	_check(companion.hp == 10 + expected_amount, "companion healed for the expected amount (%d, got hp=%d)" % [expected_amount, companion.hp])
	_check(pc.hp == pc_hp_before, "the PC's own HP is unchanged — the heal landed on the companion, not the caster")
	# consume_item() removes the entry entirely once its quantity hits 0 (party_inventory.gd) rather than
	# leaving a 0-quantity entry — confirmed by reading PartyInventory.consume_item's actual implementation.
	_check(inv.items.is_empty(), "the potion was consumed exactly once (entry removed at 0 quantity)")

	inst.queue_free()
	await process_frame

func _initialize() -> void:
	await _run_scenario(ReelFace.ResultTier.SUCCESS, false)
	await _run_scenario(ReelFace.ResultTier.CRIT_SUCCESS, true)

	print(("ITEM USE TARGETING E2E TEST PASSED" if _failures == 0 else "ITEM USE TARGETING E2E TEST FAILED: %d" % _failures))
	quit(_failures)
