extends SceneTree

## End-to-end: OverworldDemo's real FishingSpot hands off to the scene's real FishingPanel; a real
## generated shadow gets hooked, a rigged all-Critical 3-reel round grants the correct material into
## the real PartyInventory. Mirrors tests/test_overworld_demo_foraging.gd's real-scene-instance
## technique.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var spot: FishingSpot = demo.get_node("World/FishingSpot")
	_check(spot != null, "the real overworld scene places a FishingSpot named FishingSpot")

	var captured_bucket_configs: Dictionary = {}
	spot.fishing_requested.connect(func(bucket_configs: Dictionary) -> void: captured_bucket_configs = bucket_configs)
	spot.interact()
	await process_frame

	_check(demo._fishing_panel.is_open(), "interacting with the FishingSpot opens the scene's real FishingPanel")
	_check(demo._pc.movement_paused_for_test(), "opening the fishing panel pauses PC movement")
	_check(combat_handoff.is_defeated(&"FishingSpot"), "the node marked itself defeated on interact")

	# The real targeting phase generated a real random layout -- read it back rather than
	# predicting it, move the hook onto whatever the first shadow actually is, and drop the hook.
	var shadows: Array[Dictionary] = demo._fishing_panel.shadows_for_test()
	_check(shadows.size() > 0, "the real scene's FishingPanel generated at least one shadow")
	var first_shadow: Dictionary = shadows[0]
	demo._fishing_panel.move_hook_to_for_test(first_shadow["position"])
	demo._fishing_panel.press_hook_button_for_test()
	_check(demo._fishing_panel.current_phase_for_test() == &"reel_stop", "dropping the hook on a real generated shadow transitions to the reel_stop phase")

	# Bypass into a deterministic all-Critical 3-reel round to prove the grant lands in the REAL
	# scene's real PartyInventory (the exact resolve/grant math is already Task 3/5's own coverage;
	# this test's job is proving the WIRING, mirroring the Foraging plan's own scene-wiring test).
	demo._fishing_panel.begin_reel_stop_for_test(&"medium", [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])] as Array[FishingReel])
	demo._fishing_panel.press_stop_for_test(0)
	demo._fishing_panel.press_stop_for_test(1)
	demo._fishing_panel.press_stop_for_test(2)
	demo._fishing_panel.press_continue_for_test()
	await process_frame

	_check(not demo._fishing_panel.is_open(), "pressing Continue after a catch closes the panel")
	_check(not demo._pc.movement_paused_for_test(), "closing the panel resumes PC movement")
	_check(demo._party_inventory.materials.size() == 1, "the catch grants the material into the scene's real PartyInventory")
	var m: CraftingMaterial = demo._party_inventory.materials[0]
	_check(m.quality_tier == 1, "the all-Critical catch stamps quality_tier == 1 on the real granted material")

	# Regression: a MISS used to never emit fishing_completed, so PC movement was never resumed --
	# a permanent softlock (2026-08-01 final review Critical finding). The real FishingSpot node has
	# already queue_free()'d itself (deferred, and an `await process_frame` already elapsed above),
	# so it can't be re-interacted with here -- instead, drive the scene's real, already-wired
	# FishingPanel instance directly (its fishing_closed/fishing_completed connections to
	# demo._on_fishing_completed and the movement-pause lambda are the exact real wiring, identical
	# to what a second real FishingSpot trigger would exercise) into a guaranteed miss.
	demo._pc.set_movement_paused(true)
	demo._fishing_panel.open_for(captured_bucket_configs, demo._party_inventory)
	_check(demo._fishing_panel.is_open(), "re-opening the real panel starts a fresh round")
	demo._fishing_panel.begin_reel_stop_for_test(&"small", [_reel([&"fail"])] as Array[FishingReel])
	demo._fishing_panel.press_stop_for_test(0)
	demo._fishing_panel.press_continue_for_test()
	await process_frame
	_check(not demo._fishing_panel.is_open(), "pressing Continue after a miss closes the panel")
	_check(not demo._pc.movement_paused_for_test(), "closing the panel after a MISS also resumes PC movement (the Critical-bug regression)")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]
	quit()
