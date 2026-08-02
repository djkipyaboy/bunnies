extends SceneTree

## Confirms the two additional gathering nodes (2026-08-02 gathering-playtest-fixes spec section 5)
## exist in the real overworld scene, at distinct node names from the originals, and hand off
## correctly -- mirrors tests/test_overworld_demo_foraging.gd/test_overworld_demo_fishing.gd's
## real-scene-instance technique, scoped to proving the SECOND node of each kind works (the full
## grant/resolve flow is already covered by those existing tests for the first node of each).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var berries2: GatheringNode = demo.get_node("World/WildBerries2")
	_check(berries2 != null, "the real overworld scene places a second Foraging node named WildBerries2")

	berries2.interact()
	await process_frame
	_check(demo._foraging_panel.is_open(), "interacting with WildBerries2 opens the scene's real ForagingPanel")
	_check(combat_handoff.is_defeated(&"WildBerries2"), "WildBerries2 marks itself defeated independently of the original WildBerries")
	demo._foraging_panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)
	demo._foraging_panel.press_bank_for_test()
	_check(not demo._foraging_panel.is_open(), "banking closes the panel opened from WildBerries2")

	var fish2: FishingSpot = demo.get_node("World/FishingSpot2")
	_check(fish2 != null, "the real overworld scene places a second Fishing node named FishingSpot2")

	fish2.interact()
	await process_frame
	_check(demo._fishing_panel.is_open(), "interacting with FishingSpot2 opens the scene's real FishingPanel")
	_check(combat_handoff.is_defeated(&"FishingSpot2"), "FishingSpot2 marks itself defeated independently of the original FishingSpot")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]
	quit()
