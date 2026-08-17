extends SceneTree

## Regression (2026-08-17 playtest): active_minion must not survive into a new combat encounter
## via CombatHandoff — a minion still alive when a fight ends must not let the Summoner's
## Ultimate wrongly report itself as fireable in the NEXT fight (MainPhasePlan.can_stage_ultimate()
## reads combatant.active_minion != null and combatant.active_minion.is_alive()).
##
## CombatHandoff is registered as an autoload, but a bare `extends SceneTree` test script does NOT
## get the same autoload injection a real running scene gets — reference it via
## get_root().get_node("CombatHandoff") (confirmed pattern, see tests/test_combat_handoff_entry.gd).
##
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stale_active_minion_reset.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()  # defensive: don't let an earlier section's state bleed in

	var summoner: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	summoner.active_minion = MinionLibrary.make(false, &"hasty")  # simulates a fight that ended with a live minion
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]

	CombatHandoff.begin_encounter(summoner, [], inv, vault, enemy_ids,
		&"OverworldRat", "res://world/overworld_demo.tscn", Vector2(111.0, 222.0))

	_check(summoner.active_minion != null, "sanity: active_minion is set before the new encounter is built")

	var combat_scene: PackedScene = load("res://combat/combat.tscn")
	var combat: Node = combat_scene.instantiate()
	get_root().add_child(combat)
	await process_frame
	await process_frame

	_check(summoner.active_minion == null, "active_minion is reset to null when a new encounter is built from handoff (got %s)" % summoner.active_minion)

	combat.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("STALE ACTIVE MINION RESET TEST PASSED" if _failures == 0 else "STALE ACTIVE MINION RESET TEST FAILED: %d" % _failures))
	quit(_failures)
