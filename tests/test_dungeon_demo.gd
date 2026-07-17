extends SceneTree

## Headless test for the dungeon's floor-skeleton core (2026-07-17-dungeon-scene-structure-design.md
## §3.1-§3.3): floor_bounds() disjointness, _build_floors()'s stairs/exit wiring, and
## _apply_floor_change()'s pure toggle/reposition/camera logic (the synchronous half of
## travel_to_floor(), which Stairs.interact() delegates to — travel_to_floor() itself additionally
## awaits a real FadeOverlay tween, which this test deliberately doesn't drive, mirroring how
## tests/test_overworld_enemy.gd/tests/test_scene_exit.gd never await a real fade either).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# --- floor_bounds() disjointness (spec §3.1's critical precedent) ---
	var bounds: Array[Rect2] = []
	for i in range(DungeonDemo.FLOOR_COUNT):
		bounds.append(DungeonDemo.floor_bounds(i))
	for i in range(bounds.size()):
		for j in range(bounds.size()):
			if i == j:
				continue
			var a: Rect2 = bounds[i].grow(WorldGeometry.WALL_THICKNESS)
			var b: Rect2 = bounds[j].grow(WorldGeometry.WALL_THICKNESS)
			_check(not a.intersects(b), "floor %d and floor %d wall footprints never overlap" % [i, j])

	# --- _build_floors() ---
	var dungeon := DungeonDemo.new()
	dungeon._current_floor = 0
	dungeon._build_floors()

	_check(dungeon._floors.size() == 4, "_build_floors creates 4 floor containers")
	_check(dungeon._floors[0].visible == true, "floor 1 starts visible")
	_check(dungeon._floors[0].process_mode == Node.PROCESS_MODE_INHERIT, "floor 1 starts enabled")
	_check(dungeon._floors[1].visible == false, "floor 2 starts hidden")
	_check(dungeon._floors[1].process_mode == Node.PROCESS_MODE_DISABLED, "floor 2 starts disabled")
	_check(dungeon._floors[3].visible == false, "floor 4 starts hidden")

	_check(dungeon._floors[0].get_node_or_null("StairsDown") != null, "floor 1 has a StairsDown")
	_check(dungeon._floors[0].get_node_or_null("StairsUp") == null, "floor 1 has no StairsUp")
	_check(dungeon._floors[3].get_node_or_null("StairsDown") == null, "floor 4 has no StairsDown")
	_check(dungeon._floors[3].get_node_or_null("StairsUp") != null, "floor 4 has a StairsUp")

	var stairs_down_1: Stairs = dungeon._floors[0].get_node("StairsDown")
	_check(stairs_down_1.target_floor_index == 1, "floor 1's StairsDown targets floor index 1")
	_check(stairs_down_1.target_local_entry == DungeonDemo.STAIRS_UP_LOCAL, "floor 1's StairsDown lands at STAIRS_UP_LOCAL")
	_check(stairs_down_1.dungeon == dungeon, "floor 1's StairsDown is wired to this dungeon")
	_check(stairs_down_1.prompt_text == "Descend", "StairsDown's prompt_text is 'Descend'")

	var stairs_up_2: Stairs = dungeon._floors[1].get_node("StairsUp")
	_check(stairs_up_2.target_floor_index == 0, "floor 2's StairsUp targets floor index 0")
	_check(stairs_up_2.target_local_entry == DungeonDemo.STAIRS_DOWN_LOCAL, "floor 2's StairsUp lands at STAIRS_DOWN_LOCAL")
	_check(stairs_up_2.prompt_text == "Ascend", "StairsUp's prompt_text is 'Ascend'")

	_check(dungeon._floors[0].get_node_or_null("DungeonExit") != null, "floor 1 has the DungeonExit")
	_check(dungeon._floors[1].get_node_or_null("DungeonExit") == null, "floor 2 has no DungeonExit")

	# --- _apply_floor_change() (pure logic, no fade await) ---
	var pc := Node2D.new()
	dungeon._floors[0].add_child(pc)
	dungeon._pc = pc
	var camera := Camera2D.new()
	pc.add_child(camera)
	dungeon._camera = camera

	dungeon._apply_floor_change(1, DungeonDemo.STAIRS_UP_LOCAL)
	_check(dungeon._floors[0].visible == false, "_apply_floor_change hides the old floor")
	_check(dungeon._floors[0].process_mode == Node.PROCESS_MODE_DISABLED, "_apply_floor_change disables the old floor")
	_check(dungeon._floors[1].visible == true, "_apply_floor_change shows the target floor")
	_check(dungeon._floors[1].process_mode == Node.PROCESS_MODE_INHERIT, "_apply_floor_change enables the target floor")
	_check(pc.get_parent() == dungeon._floors[1], "_apply_floor_change reparents the PC into the target floor")
	var expected_pos: Vector2 = DungeonDemo.floor_bounds(1).position + DungeonDemo.STAIRS_UP_LOCAL
	_check(pc.global_position == expected_pos, "_apply_floor_change positions the PC at the target floor's entry marker")
	var expected_bounds: Rect2 = DungeonDemo.floor_bounds(1)
	_check(camera.limit_left == int(expected_bounds.position.x), "_apply_floor_change sets the camera's left bound to the target floor")
	_check(camera.limit_top == int(expected_bounds.position.y), "_apply_floor_change sets the camera's top bound to the target floor")
	_check(camera.limit_right == int(expected_bounds.end.x), "_apply_floor_change sets the camera's right bound to the target floor")
	_check(camera.limit_bottom == int(expected_bounds.end.y), "_apply_floor_change sets the camera's bottom bound to the target floor")
	_check(dungeon._current_floor == 1, "_apply_floor_change updates _current_floor")

	dungeon.free()
	quit()
