extends SceneTree

## Headless test for TypeChartPanel: dynamic grid sizing for all 8 types (2026-07-18 Light/Dark
## expansion), plus the pre-existing coverage (build correctness, highlight_attacker, drag-handle
## mouse-filter behavior, viewport clamping) that the Light/Dark rewrite had dropped.
## Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_type_chart_panel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel: TypeChartPanel = TypeChartPanel.new()
	get_root().add_child(panel)
	panel.build()

	_check(panel.TYPE_PATHS.size() == 8, "TYPE_PATHS lists 8 type resource paths (got %d)" % panel.TYPE_PATHS.size())
	_check(panel._types.size() == 8, "build() loads all 8 DamageType resources (got %d)" % panel._types.size())
	_check(panel._row_headers.size() == 8, "build() creates 8 row headers, one per type (got %d)" % panel._row_headers.size())

	var expected_width: float = TypeChartPanel.PAD * 2 + TypeChartPanel.ROWHDR_W + TypeChartPanel.CELL_W * 8.0
	var expected_height: float = TypeChartPanel.PAD * 2 + TypeChartPanel.TITLE_H + TypeChartPanel.LEGEND_H + TypeChartPanel.HEADER_H + TypeChartPanel.ROW_H * 8.0
	_check(is_equal_approx(panel.size.x, expected_width), "panel width scales to 8 columns (got %s, expected %s)" % [panel.size.x, expected_width])
	_check(is_equal_approx(panel.size.y, expected_height), "panel height scales to 8 rows (got %s, expected %s)" % [panel.size.y, expected_height])

	# Light attacking Dark reads 1.5x, matching the locked design.
	var light_index: int = -1
	var dark_index: int = -1
	for i: int in range(panel._types.size()):
		if panel._types[i].type == DamageType.Type.LIGHT:
			light_index = i
		if panel._types[i].type == DamageType.Type.DARK:
			dark_index = i
	_check(light_index != -1 and dark_index != -1, "both Light and Dark are present among the loaded types")
	_check(panel._types[light_index].multiplier_against(panel._types[dark_index]) == 1.5, "Light vs Dark reads 1.5x in the panel's own loaded data")

	# 64 data cells + 8 row headers + 8 col headers = 80 header Panels, for 8 types (was 36 + 12 for 6).
	var cells: int = 0
	for c: Node in panel.get_children():
		if c is Panel:
			cells += 1
	_check(cells == 64 + 16, "64 data cells + 16 headers built (got %d Panel children)" % cells)
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
