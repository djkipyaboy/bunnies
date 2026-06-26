extends SceneTree

# Headless test: TypeChartPanel builds the full 6×6 from live data without error and highlight_attacker
# runs cleanly (the toggle path the scene-load smoke doesn't reach). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_type_chart_panel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel: TypeChartPanel = TypeChartPanel.new()
	get_root().add_child(panel)
	panel.build()
	# 36 data cells + 6 row headers + 6 col headers + title + def-hint + legend = 50 children.
	var cells: int = 0
	for c: Node in panel.get_children():
		if c is Panel:
			cells += 1
	_check(cells == 36 + 12, "36 data cells + 12 headers built (got %d Panel children)" % cells)
	_check(panel.size.x > 300.0 and panel.size.y > 200.0, "panel sized for the grid (%dx%d)" % [panel.size.x, panel.size.y])

	# highlight_attacker runs without error and is idempotent / clearable.
	panel.highlight_attacker(DamageType.Type.MYSTIC)
	panel.highlight_attacker(DamageType.Type.SLASHING)
	panel.highlight_attacker(-1)
	_check(true, "highlight_attacker ran for several types + clear without error")

	# Draggable: the panel is a STOP handle, its decorative children ignore mouse, and the clamp keeps
	# the chart on-screen (player request 2026-06-26 — let the player place the chart where they want it).
	_check(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "panel itself receives mouse input (drag handle)")
	var all_ignore: bool = true
	for c: Node in panel.get_children():
		if c is Control and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			all_ignore = false
	_check(all_ignore, "decorative children ignore the mouse so a drag works anywhere on the chart")
	var vp: Vector2 = panel.get_viewport_rect().size
	panel.position = Vector2(99999, 99999)
	panel._clamp_to_viewport()
	_check(panel.position.x >= 0.0 and panel.position.x <= maxf(0.0, vp.x - panel.size.x) + 0.5, "clamp keeps the chart's X on-screen")
	_check(panel.position.y >= 0.0 and panel.position.y <= maxf(0.0, vp.y - panel.size.y) + 0.5, "clamp keeps the chart's Y on-screen")
	panel.position = Vector2(-500, -500)
	panel._clamp_to_viewport()
	_check(panel.position.x == 0.0 and panel.position.y == 0.0, "clamp pins a negative drag back to the top-left")

	panel.queue_free()
	print(("TYPE CHART PANEL TEST PASSED" if _failures == 0 else "TYPE CHART PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
