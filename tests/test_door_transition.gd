extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var exterior := Node2D.new()
	exterior.visible = true
	exterior.process_mode = Node.PROCESS_MODE_INHERIT
	var interior := Node2D.new()
	interior.visible = false
	interior.process_mode = Node.PROCESS_MODE_DISABLED

	# Pure static toggle logic first.
	Door.toggle_areas(exterior, interior)
	_check(not exterior.visible, "toggle_areas hides the current area")
	_check(exterior.process_mode == Node.PROCESS_MODE_DISABLED, "toggle_areas disables the current area's processing")
	_check(interior.visible, "toggle_areas shows the target area")
	_check(interior.process_mode == Node.PROCESS_MODE_INHERIT, "toggle_areas re-enables the target area's processing")

	# Instance behavior — interact() wires toggle_areas + PC teleport + camera bounds.
	var pc := Node2D.new()
	pc.global_position = Vector2(999, 999)
	var entry_marker := Marker2D.new()
	entry_marker.global_position = Vector2(160, 180)
	var camera := Camera2D.new()

	var door := Door.new()
	door.current_area = exterior
	door.target_area = interior
	door.entry_marker = entry_marker
	door.camera = camera
	door.target_camera_limits = Rect2(0, 0, 320, 240)
	door.pc = pc

	door.interact()
	_check(not exterior.visible, "interact() hides the current area")
	_check(interior.visible, "interact() shows the target area")
	_check(pc.global_position == Vector2(160, 180), "interact() teleports the PC to the entry marker")
	_check(camera.limit_left == 0 and camera.limit_top == 0, "interact() sets the camera's top-left bound")
	_check(camera.limit_right == 320 and camera.limit_bottom == 240, "interact() sets the camera's bottom-right bound")

	# set_highlighted() with no highlight_visual assigned — must no-op, not crash.
	var bare_door := Door.new()
	bare_door.set_highlighted(true)
	_check(true, "set_highlighted() with no highlight_visual does not crash")

	# set_highlighted() with a highlight_visual assigned — toggles its alpha.
	var arrow := Polygon2D.new()
	door.highlight_visual = arrow
	door.set_highlighted(true)
	_check(arrow.modulate.a == 1.0, "set_highlighted(true) brightens the highlight_visual to full alpha")
	door.set_highlighted(false)
	_check(is_equal_approx(arrow.modulate.a, Door.DIM_ALPHA), "set_highlighted(false) dims the highlight_visual back down")

	# None of these Node-derived objects were ever added to a tree — free them explicitly
	# or the process reports leaked instances at exit.
	arrow.free()
	bare_door.free()
	door.free()
	camera.free()
	entry_marker.free()
	pc.free()
	interior.free()
	exterior.free()
	quit()
