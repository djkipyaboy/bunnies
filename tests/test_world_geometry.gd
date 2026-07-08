extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Pure geometry — four wall segments framing a bounds rect.
	var parent := Node2D.new()
	WorldGeometry.add_boundary_walls(parent, Rect2(0, 0, 100, 50))
	_check(parent.get_child_count() == 4, "add_boundary_walls adds exactly 4 wall segments")

	var left_shape: RectangleShape2D = parent.get_child(0).get_child(0).shape
	_check(parent.get_child(0).position.is_equal_approx(Vector2(-8, 25)), "left wall sits flush against the west edge")
	_check(left_shape.size.is_equal_approx(Vector2(16, 82)), "left wall spans the bounds height plus corner overlap")

	var right_shape: RectangleShape2D = parent.get_child(1).get_child(0).shape
	_check(parent.get_child(1).position.is_equal_approx(Vector2(108, 25)), "right wall sits flush against the east edge")
	_check(right_shape.size.is_equal_approx(Vector2(16, 82)), "right wall spans the bounds height plus corner overlap")

	var top_shape: RectangleShape2D = parent.get_child(2).get_child(0).shape
	_check(parent.get_child(2).position.is_equal_approx(Vector2(50, -8)), "top wall sits flush against the north edge")
	_check(top_shape.size.is_equal_approx(Vector2(132, 16)), "top wall spans the bounds width plus corner overlap")

	var bottom_shape: RectangleShape2D = parent.get_child(3).get_child(0).shape
	_check(parent.get_child(3).position.is_equal_approx(Vector2(50, 58)), "bottom wall sits flush against the south edge")
	_check(bottom_shape.size.is_equal_approx(Vector2(132, 16)), "bottom wall spans the bounds width plus corner overlap")

	# add_solid_collider — a single StaticBody2D centered on the given rect.
	var solid_parent := Node2D.new()
	WorldGeometry.add_solid_collider(solid_parent, Rect2(10, 20, 40, 30))
	_check(solid_parent.get_child_count() == 1, "add_solid_collider adds exactly one StaticBody2D")
	var solid_shape: RectangleShape2D = solid_parent.get_child(0).get_child(0).shape
	_check(solid_parent.get_child(0).position.is_equal_approx(Vector2(30, 35)), "add_solid_collider centers on the given rect")
	_check(solid_shape.size.is_equal_approx(Vector2(40, 30)), "add_solid_collider matches the given rect's size")

	# Regression (carried over from the town demo's playtest-fix pass): the exterior plaza
	# and the interior shop floor must never occupy overlapping world space. Door.toggle_areas()
	# hides an area with visible = false / PROCESS_MODE_DISABLED — neither disables physics
	# collision in Godot, so overlapping bounds would put invisible walls (and spawned NPCs)
	# inside the "closed" area's live geometry even while it's supposed to be inaccessible.
	var exterior_walled: Rect2 = TownDemo.EXTERIOR_BOUNDS.grow(WorldGeometry.WALL_THICKNESS)
	var interior_walled: Rect2 = TownDemo.INTERIOR_BOUNDS.grow(WorldGeometry.WALL_THICKNESS)
	_check(not exterior_walled.intersects(interior_walled), "exterior and interior wall footprints never overlap")

	parent.free()
	solid_parent.free()
	quit()
