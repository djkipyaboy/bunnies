extends SceneTree

# Headless test: EventLogPanel (2026-07-13-overworld-event-log-design.md §4). A pure view widget —
# no CombatHandoff dependency of its own, driven entirely by refresh()/append_line() and (for the
# opacity behavior) the _for_test() hooks below instead of a real mouse/renderer.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_event_log_panel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel: EventLogPanel = EventLogPanel.new()
	get_root().add_child(panel)
	panel.build()

	_check(is_equal_approx(panel.modulate.a, EventLogPanel.TRANSLUCENT_ALPHA), "starts translucent (got %f)" % panel.modulate.a)

	panel.refresh(["Picked up: Shiny Trinket", "Encounter started: Cluny's Rat"])
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "refresh() renders the seeded lines")
	_check(panel.text_for_test().find("Cluny's Rat") != -1, "refresh() renders every seeded line")

	panel.append_line("Won: Cluny's Rat")
	_check(panel.text_for_test().find("Won: Cluny's Rat") != -1, "append_line() adds a new line")
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "append_line() does not clear prior lines")

	panel.refresh(["Only line"])
	_check(panel.text_for_test().find("Won: Cluny's Rat") == -1, "refresh() DOES clear prior lines (unlike append_line)")
	_check(panel.text_for_test().find("Only line") != -1, "refresh() shows the new seeded lines")

	panel.simulate_mouse_entered_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.OPAQUE_ALPHA), "mouse_entered goes fully opaque (got %f)" % panel.modulate.a)

	panel.simulate_mouse_exited_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.TRANSLUCENT_ALPHA), "mouse_exited returns to translucent (got %f)" % panel.modulate.a)

	panel.queue_free()

	print(("EVENT LOG PANEL TEST PASSED" if _failures == 0 else "EVENT LOG PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
