# tests/test_overworld_demo_respawn_combatants.gd
extends SceneTree

## Headless test for the "Respawn Combatants" debug button (2026-08-13 playtest round 2 request) --
## mirrors tests/test_overworld_demo_respawn_gathering_nodes.gd's real-scene-instance technique.
## Simulates a defeated encounter directly (mark_defeated() + freeing the live node) rather than
## driving a full combat round-trip -- that combat-win path is already covered elsewhere; this test
## is only about the debug button's own respawn logic.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var rat: Node = demo.get_node("World/OverworldRat")
	_check(rat != null, "OverworldRat exists before defeat")
	var ambush: Node = demo.get_node("World/BanditAmbush")
	_check(ambush != null, "BanditAmbush exists before defeat")

	combat_handoff.mark_defeated(&"OverworldRat")
	combat_handoff.mark_defeated(&"BanditAmbush")
	demo.get_node("World").remove_child(rat)
	rat.queue_free()
	demo.get_node("World").remove_child(ambush)
	ambush.queue_free()
	await process_frame
	_check(demo.get_node_or_null("World/OverworldRat") == null, "OverworldRat removed after simulated defeat")
	_check(demo.get_node_or_null("World/BanditAmbush") == null, "BanditAmbush removed after simulated defeat")

	demo.press_respawn_combatants_for_test()
	await process_frame
	_check(not combat_handoff.is_defeated(&"OverworldRat"), "respawn clears OverworldRat's defeated flag")
	_check(not combat_handoff.is_defeated(&"BanditAmbush"), "respawn clears BanditAmbush's defeated flag")
	var respawned_rat: Node = demo.get_node_or_null("World/OverworldRat")
	_check(respawned_rat != null, "respawn re-creates OverworldRat in the tree")
	_check(respawned_rat != rat, "the respawned rat is a fresh instance, not the freed original")
	_check(demo.get_node_or_null("World/BanditAmbush") != null, "respawn re-creates BanditAmbush in the tree")

	_check(demo.get_node_or_null("World/OverworldFerret") != null, "respawn leaves an already-alive combatant (OverworldFerret) in place")
	_check(demo.get_node_or_null("World/OverworldStoat") != null, "respawn leaves an already-alive combatant (OverworldStoat) in place")

	print(("RESPAWN COMBATANTS TEST PASSED" if _failures == 0 else "RESPAWN COMBATANTS TEST FAILED: %d" % _failures))
	quit(_failures)
