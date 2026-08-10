# tests/test_pc_controller_moved_signal.gd
extends SceneTree

## Headless test for PCController's new `moved` signal (2026-08-10 quest-popups-and-tutorial-wiring
## plan Task 9) — fires exactly once, on the first nonzero movement input.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var pc := PCController.new()
	var fire_count_box: Array = [0]
	pc.moved.connect(func() -> void: fire_count_box[0] += 1)

	# Zero input: no signal.
	Input.action_press("move_right")
	Input.action_release("move_right")
	pc._physics_process(0.016)
	_check(fire_count_box[0] == 0, "no signal on a frame with zero net movement input")

	# Nonzero input: fires once.
	Input.action_press("move_right")
	pc._physics_process(0.016)
	_check(fire_count_box[0] == 1, "fires once on the first nonzero movement input (got %d)" % fire_count_box[0])

	# Stays fired — doesn't re-fire on subsequent nonzero-input frames.
	pc._physics_process(0.016)
	_check(fire_count_box[0] == 1, "does not fire again on a later nonzero-input frame (got %d)" % fire_count_box[0])

	Input.action_release("move_right")
	pc.free()
	print(("PC CONTROLLER MOVED SIGNAL TEST PASSED" if _failures == 0 else "PC CONTROLLER MOVED SIGNAL TEST FAILED: %d" % _failures))
	quit(_failures)
