extends SceneTree

# Headless test: the 2026-07-17 per-enemy Amber-on-kill reward (combat.gd's _on_enemy_defeated).
# Uses the overworld-handoff entry point (mirrors test_combat_xp.gd) so combat starts immediately
# with real _pcs/_enemies and a real _party_inventory, then kills enemies directly via take_damage()
# rather than driving a full turn-based fight — this only needs to prove the Amber-reward wiring +
# result-card display, not the combat loop itself (already covered elsewhere).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_amber.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat", &"ferret"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"AmberTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._enemies.size() == 2, "handoff builds both enemies from CombatHandoff.enemy_ids")
	_check(inst._enemies[0].amber_reward == 5, "the rat carries its authored Amber reward (got %d)" % inst._enemies[0].amber_reward)
	_check(inst._enemies[1].amber_reward == 8, "the ferret carries its authored Amber reward (got %d)" % inst._enemies[1].amber_reward)
	_check(inv.amber == 0, "amber starts at 0 before any kill")

	# --- Killing the first enemy (rat) awards its flat Amber reward ---
	inst._enemies[0].take_damage(9999)
	_check(not inst._enemies[0].is_alive(), "the rat is actually dead")
	_check(inv.amber == 5, "the rat's kill grants 5 Amber to the party (got %d)" % inv.amber)
	_check(inst._fight_amber_gained == 5, "the fight-total Amber counter accumulates (got %d)" % inst._fight_amber_gained)

	# --- A second kill stacks further amber (not a one-time award) ---
	inst._enemies[1].take_damage(9999)
	_check(inv.amber == 13, "the ferret's kill stacks another 8 Amber (5 + 8 = 13, got %d)" % inv.amber)
	_check(inst._fight_amber_gained == 13, "the fight-total counter reflects both kills (got %d)" % inst._fight_amber_gained)

	# --- Total-fight Amber is surfaced on the result card once combat actually ends ---
	inst._turn_manager.advance_turn()   # both real enemies are dead -> this ends combat as a win
	_check(inst._overlay.visible, "the result card shows once combat ends")
	var result_label: Label = inst._overlay.get_node("ResultLabel")
	_check(result_label.text.find("+%d Amber" % inst._fight_amber_gained) != -1, "the result card shows the total Amber gained this fight (got '%s')" % result_label.text)

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory exists, Amber must not be granted or crash ---
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
	_check(not standalone._enemies[0].is_alive(), "the standalone enemy is also actually dead")
	_check(standalone._fight_amber_gained == 0, "standalone mode never accumulates Amber (nothing to grant it into)")

	standalone.queue_free()
	await process_frame

	print(("COMBAT AMBER TEST PASSED" if _failures == 0 else "COMBAT AMBER TEST FAILED: %d" % _failures))
	quit(_failures)
