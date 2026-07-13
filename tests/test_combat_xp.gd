extends SceneTree

# Headless test: the 2026-07-12 minimal XP-per-kill loop (combat.gd's _on_enemy_defeated). Uses
# the overworld-handoff entry point (mirrors test_combat_handoff_entry.gd) so combat starts
# immediately with real _pcs/_enemies, then kills an enemy directly via take_damage() rather than
# driving a full turn-based fight through the UI — this only needs to prove the defeated-signal
# wiring + XP award, not the combat loop itself (already covered elsewhere).
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_xp.gd

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
	var enemy_ids: Array[StringName] = [&"rat", &"ferret"]
	CombatHandoff.begin_encounter(pc, [companion], inv, vault, enemy_ids,
		&"XPTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._enemies.size() == 2, "handoff builds both enemies from CombatHandoff.enemy_ids")
	_check(pc.xp == 0, "xp starts at 0 before any kill")
	_check(companion.xp == 0, "companion's xp also starts at 0")

	# --- Killing the first enemy awards flat XP to every LIVING pc ---
	inst._enemies[0].take_damage(9999)
	_check(not inst._enemies[0].is_alive(), "the first enemy is actually dead")
	_check(pc.xp == Combat.ENEMY_XP_REWARD, "the PC gains ENEMY_XP_REWARD xp on a kill (got %d)" % pc.xp)
	_check(companion.xp == Combat.ENEMY_XP_REWARD, "the living companion also gains xp on the same kill")

	# --- A second kill stacks further xp (not a one-time award) ---
	inst._enemies[1].take_damage(9999)
	_check(pc.xp == Combat.ENEMY_XP_REWARD * 2, "a second kill stacks another ENEMY_XP_REWARD (got %d)" % pc.xp)

	# --- Total-fight XP is tracked and surfaced on the result card once combat actually ends
	# (player direction 2026-07-12: XP gain wasn't visible enough anywhere in the log alone) ---
	_check(inst._fight_xp_gained == Combat.ENEMY_XP_REWARD * 2, "the fight-total XP counter accumulates across kills (got %d)" % inst._fight_xp_gained)
	inst._turn_manager.advance_turn()   # both real enemies are dead -> this ends combat as a win
	_check(inst._overlay.visible, "the result card shows once combat ends")
	var result_label: Label = inst._overlay.get_node("ResultLabel")
	_check(result_label.text.find("+%d XP" % inst._fight_xp_gained) != -1, "the result card shows the total XP gained this fight (got '%s')" % result_label.text)

	# --- A dead PC does not gain xp from a kill after its own death ---
	pc.take_damage(9999)
	_check(not pc.is_alive(), "the PC is now dead (for this assertion only)")
	# Re-defeat is impossible (both real enemies are already dead), so directly exercise the
	# handler to prove the is_alive() guard, mirroring how other combat.gd tests call handlers
	# directly rather than re-deriving game state to force a scenario.
	var enemy_stub: Combatant = EnemyLibrary.make(&"rat")
	inst._on_enemy_defeated(enemy_stub)
	_check(pc.xp == Combat.ENEMY_XP_REWARD * 2, "a dead PC's xp does not increase from a later kill")
	_check(companion.xp == Combat.ENEMY_XP_REWARD * 3, "a living companion still gains xp even after the PC has died")

	inst.queue_free()
	await process_frame

	print(("COMBAT XP TEST PASSED" if _failures == 0 else "COMBAT XP TEST FAILED: %d" % _failures))
	quit(_failures)
