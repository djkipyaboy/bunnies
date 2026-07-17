extends SceneTree

# Headless test: ally-target selection (2026-07-16 combat item-use targeting design §2/§3.4). Drives
# the real combat.tscn scene via the CombatHandoff entry point (mirrors tests/test_combat_xp.gd) with a
# 2-PC party so retargeting between allies is meaningful.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ally_targeting.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var companion: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [companion], inv, vault, enemy_ids,
		&"AllyTargetingTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	# Drive turns until it's a PC's turn awaiting a spin (enemy turns auto-resolve on a timer; this
	# loop only advances frames, mirroring tests/test_scene_party_smoke.gd's guard style).
	var guard: int = 0
	while is_instance_valid(inst) and not inst._awaiting_player_spin and guard < 200:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin, "reached a PC's pre-spin window within the frame guard")
	_check(inst._attacker.is_player, "the awaiting turn belongs to a player-side combatant")

	# Default: the active combatant's own panel is the ally target (§2).
	var active: Combatant = inst._attacker
	_check(inst._ally_target == active, "ally target defaults to the active combatant's own panel")
	_check((inst._panels[active] as CombatantPanel).has_theme_stylebox_override("panel"), "active combatant's panel shows the green outline by default")

	# Retarget to the other PC via the same hook the click-catcher calls.
	var other_pc: Combatant = companion if active == pc else pc
	inst._select_ally_target(other_pc)
	_check(inst._ally_target == other_pc, "_select_ally_target retargets to the clicked ally")
	_check((inst._panels[other_pc] as CombatantPanel).has_theme_stylebox_override("panel"), "the newly-targeted panel shows the green outline")
	_check(not (inst._panels[active] as CombatantPanel).has_theme_stylebox_override("panel"), "the previously-targeted panel's outline clears")

	# Rejects a dead ally.
	other_pc.take_damage(9999)
	_check(not other_pc.is_alive(), "the retargeted ally is now dead (for this assertion only)")
	inst._select_ally_target(active)  # reset to a living ally first
	inst._select_ally_target(other_pc)
	_check(inst._ally_target == active, "_select_ally_target rejects a dead ally — target unchanged")

	# Rejects null.
	inst._select_ally_target(null)
	_check(inst._ally_target == active, "_select_ally_target rejects null — target unchanged")

	inst.queue_free()
	await process_frame

	print(("ALLY TARGETING TEST PASSED" if _failures == 0 else "ALLY TARGETING TEST FAILED: %d" % _failures))
	quit(_failures)
