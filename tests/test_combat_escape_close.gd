extends SceneTree

# Headless test for the 2026-08-15 playtester note, combat.gd's half — this is combat.gd's first
# keyboard input handler at all (every other panel here was previously button-only, per the
# _event_log_button comment at combat.gd's own _ready()). Covers: Escape closes the Item menu, the
# Ability menu, and the Type Chart (reusing _on_type_chart_toggle_pressed()'s own off-path so the
# button text/highlight stay in sync); Escape leaves the Event Log alone (non-modal by design); and
# Escape is a no-op when nothing is open.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_escape_close.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _escape_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	Combat._pc_class_ids = [&"warrior"]
	Combat._enemy_ids = [&"rat"]
	Combat._dummies_enabled = false
	Combat._endgame_enabled = false

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	inst._start_combat()
	await process_frame

	# --- Escape is a no-op when nothing is open (doesn't error, doesn't touch the Event Log) ---
	_check(not inst._event_log_panel.visible, "the Event Log starts hidden in combat.gd (button-toggled only, unchanged by this task)")
	inst._unhandled_input(_escape_event())
	_check(not inst._event_log_panel.visible, "Escape with nothing open leaves the Event Log untouched")

	# --- Escape closes the Item menu ---
	inst._item_menu.visible = true
	inst._unhandled_input(_escape_event())
	_check(not inst._item_menu.visible, "Escape closed the open Item menu")

	# --- Escape closes the Ability menu ---
	inst._ability_menu.visible = true
	inst._unhandled_input(_escape_event())
	_check(not inst._ability_menu.visible, "Escape closed the open Ability menu")

	# --- Escape closes the Type Chart via the same off-path the button uses (text/highlight stay in sync) ---
	inst._on_type_chart_toggle_pressed()
	_check(inst._type_chart.visible, "Type Chart opened via its own toggle button")
	_check(inst._type_chart_button.text == "Type Chart: ON", "the button label reflects the open state")
	inst._unhandled_input(_escape_event())
	_check(not inst._type_chart.visible, "Escape closed the open Type Chart")
	_check(inst._type_chart_button.text == "Type Chart: OFF", "Escape-closing the Type Chart also resets the button label")

	inst.queue_free()
	await process_frame
	print(("COMBAT ESCAPE CLOSE TEST PASSED" if _failures == 0 else "COMBAT ESCAPE CLOSE TEST FAILED: %d" % _failures))
	quit(_failures)
