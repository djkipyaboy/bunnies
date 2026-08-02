extends SceneTree

## FishingPanel: view over FishingShadowGenerator/FishingMinigame (2026-08-01
## gathering-profession-minigames spec section 3). Mirrors RandomEncounterPanel's
## SceneTree/_initialize()/press_*_for_test structure and "clear and rebuild children per phase"
## convention.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _bucket_configs() -> Dictionary:
	return {
		&"small": {"material_type": &"fish_small", "material_display_name": "Minnow", "quantity": 1},
		&"medium": {"material_type": &"fish_medium", "material_display_name": "Freshwater Fish", "quantity": 2},
		&"large": {"material_type": &"fish_large", "material_display_name": "Prize Bass", "quantity": 1},
	}

## Builds a FishingReel whose faces are exactly [param tiers], in order, un-shuffled.
func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var panel: FishingPanel = FishingPanel.new()
	get_root().add_child(panel)
	await process_frame

	# --- Targeting phase, with a forced deterministic shadow layout ---
	var forced_shadows: Array[Dictionary] = [
		{"position": Vector2(100.0, 100.0), "size_bucket": &"small", "radius": 16.0},
		{"position": Vector2(300.0, 150.0), "size_bucket": &"large", "radius": 32.0},
	]
	panel.open_for(_bucket_configs(), inv, forced_shadows)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visible")
	_check(panel.current_phase_for_test() == &"targeting", "opens into the targeting phase")
	_check(panel.shadows_for_test().size() == 2, "the forced shadow layout is used as-is (not randomly regenerated)")

	# A miss: hook far from both shadows, pressing the button does nothing.
	panel.move_hook_to_for_test(Vector2(0.0, 0.0))
	panel.press_hook_button_for_test()
	_check(panel.current_phase_for_test() == &"targeting", "pressing Drop Hook while not overlapping any shadow stays in targeting phase")

	# A hit: move onto the small shadow exactly, drop the hook.
	panel.move_hook_to_for_test(Vector2(100.0, 100.0))
	panel.press_hook_button_for_test()
	_check(panel.current_phase_for_test() == &"reel_stop", "pressing Drop Hook while overlapping a shadow transitions to the reel_stop phase")
	_check(forced_shadows.size() == 2, "open_for() copies forced_shadows -- the hook-drop's internal remove_at() must not mutate the caller's original array")

	# --- Reel-stop phase + resolution + grant, via the deterministic test-only bypass ---
	# (re-open fresh so this part of the test is independent of the targeting-phase hit above)
	panel.open_for(_bucket_configs(), inv, forced_shadows)
	panel.begin_reel_stop_for_test(&"medium", [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])] as Array[FishingReel])
	_check(panel.current_phase_for_test() == &"reel_stop", "begin_reel_stop_for_test enters the reel_stop phase directly")
	_check(panel.reel_label_font_size_for_test(0) == FishingPanel.CRITICAL_FONT_SIZE,
		"a reel currently showing Critical renders at the smaller CRITICAL_FONT_SIZE (spec: a genuine precision reward)")

	var completed_events: Array = []   # [{"name": String, "quantity": int}]
	panel.fishing_completed.connect(func(item_name: String, quantity: int) -> void:
		completed_events.append({"name": item_name, "quantity": quantity}))
	var closed_count: Array = [0]
	panel.fishing_closed.connect(func() -> void: closed_count[0] += 1)

	panel.advance_for_test(1.0)   # prove ticking doesn't crash; the rigged reels are all-critical regardless of index
	panel.press_stop_for_test(0)
	panel.press_stop_for_test(1)
	panel.press_stop_for_test(2)
	panel.press_continue_for_test()

	_check(inv.materials.size() == 1, "an all-Critical 3-reel catch grants exactly one CraftingMaterial")
	var m: CraftingMaterial = inv.materials[0]
	_check(m.material_type == &"fish_medium", "the granted material matches the medium bucket's config")
	_check(m.quantity == 4, "medium bucket base quantity 2, all-Critical quantity_multiplier 2 -> 4")
	_check(m.quality_tier == 1, "an all-Critical catch stamps quality_tier == 1")
	_check(completed_events.size() == 1 and completed_events[0]["name"] == "Freshwater Fish", "fishing_completed fires with the caught item's display name")
	_check(not panel.is_open(), "pressing Continue after a catch closes the panel")
	_check(closed_count[0] == 1, "fishing_closed also fires on a catch (the unconditional close signal)")

	# --- A no-catch case grants nothing and does not emit fishing_completed, but fishing_closed
	# still fires -- this is the fix for the Critical bug where a miss left the panel closing
	# with no signal to resume PC movement on.
	var inv2: PartyInventory = PartyInventory.new()
	panel.open_for(_bucket_configs(), inv2, forced_shadows)
	panel.begin_reel_stop_for_test(&"small", [_reel([&"fail"])] as Array[FishingReel])
	_check(panel.reel_label_font_size_for_test(0) == FishingPanel.NORMAL_FONT_SIZE,
		"a reel currently showing Fail renders at the normal (larger) font size, distinct from Critical's")
	panel.press_stop_for_test(0)
	panel.press_continue_for_test()
	_check(inv2.materials.is_empty(), "a Fail on a 1-reel fish grants nothing")
	_check(completed_events.size() == 1, "fishing_completed does not fire again on a no-catch round")
	_check(closed_count[0] == 2, "fishing_closed fires exactly once for the no-catch round even though fishing_completed does not fire")

	panel.free()
	quit()
