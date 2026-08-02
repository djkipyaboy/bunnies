extends SceneTree

## End-to-end: OverworldDemo's real "Wild Berries" GatheringNode hands off to the scene's real
## ForagingPanel, banking grants the material into the real PartyInventory and shows the pickup
## label -- mirrors tests/test_overworld_demo_npcs.gd's real-scene-instance technique (this project
## has repeatedly found wiring-only bugs, e.g. the 2026-07-12 bench-wipe and 2026-07-17
## shop-stock-reset bugs, that only a real-scene test catches).

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

	var berries: GatheringNode = demo.get_node("World/WildBerries")
	_check(berries != null, "the real overworld scene places a GatheringNode named WildBerries")

	berries.interact()
	await process_frame

	_check(demo._foraging_panel.is_open(), "interacting with the Wild Berries node opens the scene's real ForagingPanel")
	_check(demo._pc.movement_paused_for_test(), "opening the foraging panel pauses PC movement")

	demo._foraging_panel.press_bank_for_test()
	await process_frame

	_check(not demo._foraging_panel.is_open(), "banking closes the panel")
	_check(not demo._pc.movement_paused_for_test(), "banking resumes PC movement")
	_check(demo._party_inventory.materials.size() == 1, "banking grants the material into the scene's real PartyInventory")
	var m: CraftingMaterial = demo._party_inventory.materials[0]
	_check(m.material_type == &"forage_herb", "the granted material is the Wild Berries node's forage_herb type")
	_check(combat_handoff.is_defeated(&"WildBerries"), "the node marked itself defeated on interact")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]
	quit()
