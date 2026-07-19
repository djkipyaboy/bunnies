extends SceneTree

## Headless test for TypeChartPanel's dynamic grid sizing (2026-07-18 Light/Dark expansion) —
## confirms the panel renders all 8 types, not just the original hardcoded 6.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var panel := TypeChartPanel.new()
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

	panel.free()
	quit()
