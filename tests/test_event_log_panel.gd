extends SceneTree

# Headless test: EventLogPanel (2026-07-13-event-log-tabs-design.md §4). A pure view widget — no
# CombatHandoff dependency of its own, driven entirely by refresh()/append_line() (now categorized)
# and the _for_test() hooks below instead of a real mouse/renderer.
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
	_check(panel.mouse_filter == Control.MOUSE_FILTER_PASS, "the panel's mouse_filter is PASS so background clicks reach whatever's underneath")

	var seed_entries: Array[Dictionary] = [
		{"line": "Picked up: Shiny Trinket", "category": &"loot"},
		{"line": "Encounter started: Cluny's Rat", "category": &"combat"},
	]
	panel.refresh(seed_entries)
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "refresh() renders the seeded lines")
	_check(panel.text_for_test().find("Cluny's Rat") != -1, "refresh() renders every seeded line (default tab is All)")

	panel.append_line("Won: Cluny's Rat", &"combat")
	_check(panel.text_for_test().find("Won: Cluny's Rat") != -1, "append_line() adds a new line")
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "append_line() does not clear prior lines")

	panel.refresh([{"line": "Only line", "category": &"loot"}])
	_check(panel.text_for_test().find("Won: Cluny's Rat") == -1, "refresh() DOES clear prior lines (unlike append_line)")
	_check(panel.text_for_test().find("Only line") != -1, "refresh() shows the new seeded lines")

	# --- Tabs (2026-07-13-event-log-tabs-design.md §4) ---
	var tabbed_entries: Array[Dictionary] = [
		{"line": "Picked up: Shiny Trinket", "category": &"loot"},
		{"line": "Encounter started: Cluny's Rat", "category": &"combat"},
		{"line": "Recruited Basil to the party", "category": &"party"},
	]
	panel.refresh(tabbed_entries)
	_check(panel.text_for_test().find("Shiny Trinket") != -1 and panel.text_for_test().find("Cluny's Rat") != -1 and panel.text_for_test().find("Basil") != -1,
		"the default All tab shows every category")

	panel.select_tab_for_test(&"loot")
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "the Loot tab shows loot lines")
	_check(panel.text_for_test().find("Cluny's Rat") == -1, "the Loot tab hides combat lines")
	_check(panel.text_for_test().find("Basil") == -1, "the Loot tab hides party lines")

	panel.select_tab_for_test(&"combat")
	_check(panel.text_for_test().find("Cluny's Rat") != -1, "the Combat tab shows combat lines")
	_check(panel.text_for_test().find("Shiny Trinket") == -1, "the Combat tab hides loot lines")

	panel.select_tab_for_test(&"party")
	_check(panel.text_for_test().find("Basil") != -1, "the Party tab shows party lines")
	_check(panel.text_for_test().find("Cluny's Rat") == -1, "the Party tab hides combat lines")

	# append_line() re-renders immediately only if it matches the currently active tab.
	panel.append_line("Benched Basil", &"party")
	_check(panel.text_for_test().find("Benched Basil") != -1, "append_line() to the currently active tab's category re-renders immediately")
	panel.append_line("Gathered: Wild Berries x1", &"loot")
	_check(panel.text_for_test().find("Wild Berries") == -1, "append_line() to a NON-active category does not appear until that tab is selected")
	panel.select_tab_for_test(&"loot")
	_check(panel.text_for_test().find("Wild Berries") != -1, "switching to the matching tab reveals the entry that arrived while it wasn't active")

	panel.select_tab_for_test(&"")
	_check(panel.text_for_test().find("Wild Berries") != -1 and panel.text_for_test().find("Benched Basil") != -1, "switching back to All shows everything again")

	panel.simulate_mouse_entered_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.OPAQUE_ALPHA), "mouse_entered goes fully opaque (got %f)" % panel.modulate.a)

	panel.simulate_mouse_exited_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.TRANSLUCENT_ALPHA), "mouse_exited returns to translucent (got %f)" % panel.modulate.a)

	panel.queue_free()

	print(("EVENT LOG PANEL TEST PASSED" if _failures == 0 else "EVENT LOG PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
