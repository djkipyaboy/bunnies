# tests/test_overworld_demo_respawn_gathering_nodes.gd
extends SceneTree

## Headless test for the "Respawn Gathering Nodes" debug button (2026-08-10 quest-system-and-tutorial
## design §12) — mirrors tests/test_overworld_demo_gathering_content.gd's real-scene-instance technique.

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

	var berries: GatheringNode = demo.get_node("World/WildBerries")
	_check(berries != null, "WildBerries exists before defeat")
	berries.interact()
	await process_frame
	demo._foraging_panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)
	demo._foraging_panel.press_bank_for_test()
	await process_frame
	_check(combat_handoff.is_defeated(&"WildBerries"), "WildBerries is defeated after banking")
	_check(demo.get_node_or_null("World/WildBerries") == null, "WildBerries removed itself from the tree once defeated")

	demo.press_respawn_gathering_nodes_for_test()
	await process_frame
	_check(not combat_handoff.is_defeated(&"WildBerries"), "respawn clears WildBerries' defeated flag")
	var respawned: GatheringNode = demo.get_node_or_null("World/WildBerries")
	_check(respawned != null, "respawn re-creates WildBerries in the tree")
	_check(respawned != berries, "the respawned node is a fresh instance, not the freed original")

	_check(demo.get_node_or_null("World/WildBerries2") != null, "respawn leaves an already-alive node (WildBerries2) in place")

	print(("RESPAWN GATHERING NODES TEST PASSED" if _failures == 0 else "RESPAWN GATHERING NODES TEST FAILED: %d" % _failures))
	quit(_failures)
