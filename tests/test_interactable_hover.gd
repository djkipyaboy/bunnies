extends SceneTree

## Headless test for Interactable's hover_description/hover_started/hover_ended (Plan 3, world
## hover tooltips, 2026-08-10 quest-system-and-tutorial design §10). Interactable is normally driven
## by real mouse input in a live scene, so this test emits mouse_entered/mouse_exited directly
## rather than simulating actual mouse motion — proving the wiring, not the input pipeline.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var plain := Interactable.new()
	get_root().add_child(plain)
	await process_frame
	_check(not plain.input_pickable, "an Interactable with no hover_description leaves input_pickable false")

	var hoverable := Interactable.new()
	hoverable.hover_description = "Town quest board — accept and turn in quests here."
	get_root().add_child(hoverable)
	await process_frame
	_check(hoverable.input_pickable, "setting hover_description enables input_pickable")

	var started: Array[int] = [0]
	var ended: Array[int] = [0]
	hoverable.hover_started.connect(func() -> void: started[0] += 1)
	hoverable.hover_ended.connect(func() -> void: ended[0] += 1)

	hoverable.mouse_entered.emit()
	_check(started[0] == 1, "mouse_entered triggers hover_started")
	hoverable.mouse_exited.emit()
	_check(ended[0] == 1, "mouse_exited triggers hover_ended")

	plain.free()
	hoverable.free()
	print(("INTERACTABLE HOVER TEST PASSED" if _failures == 0 else "INTERACTABLE HOVER TEST FAILED: %d" % _failures))
	quit(_failures)
