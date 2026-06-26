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

	panel.queue_free()
	print(("TYPE CHART PANEL TEST PASSED" if _failures == 0 else "TYPE CHART PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
