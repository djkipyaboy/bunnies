extends SceneTree

# Headless test: PCController.movement_velocity — pure velocity calc so the movement-pause hook
# (used while InventoryMenuPanel is open) is unit-testable without a running physics frame or
# the Input singleton.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_pc_controller_movement_pause.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(PCController.movement_velocity(Vector2(1, 0), 90.0, false) == Vector2(90.0, 0.0), "unpaused moves at full speed")
	_check(PCController.movement_velocity(Vector2(1, 0), 90.0, true) == Vector2.ZERO, "paused yields zero velocity regardless of input")
	_check(PCController.movement_velocity(Vector2.ZERO, 90.0, false) == Vector2.ZERO, "no input yields zero velocity")

	var pc: PCController = PCController.new()
	_check(not pc.movement_paused_for_test(), "PCController starts unpaused")
	pc.set_movement_paused(true)
	_check(pc.movement_paused_for_test(), "set_movement_paused(true) pauses")
	pc.set_movement_paused(false)
	_check(not pc.movement_paused_for_test(), "set_movement_paused(false) resumes")
	pc.free()

	print(("PC CONTROLLER MOVEMENT PAUSE TEST PASSED" if _failures == 0 else "PC CONTROLLER MOVEMENT PAUSE TEST FAILED: %d" % _failures))
	quit(_failures)
