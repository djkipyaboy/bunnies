extends SceneTree

## Headless test: TeamUpPanel must be a real, opaque, click-blocking modal confined to the CENTER
## BAND between the two combatant columns (x≈340..1260), not a literal full-screen overlay with an
## unstyled (theme-default) background — playtest 2026-07-31 found it overlapping/see-through
## against the reel strips and ability-toggle button rows.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_center_band.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var panel: TeamUpPanel = TeamUpPanel.new()
	root.add_child(panel)  # _ready() must run before we inspect rect/style — see
	# tests/test_combatant_panel_bind_shows_existing_effects.gd's identical established pattern.
	await process_frame
	await process_frame

	_check(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "explicitly blocks mouse input to whatever's behind it")

	var left_column_right_edge: float = 324.0   # party column: x=24, width 300
	var enemy_column_left_edge: float = 1276.0
	_check(panel.position.x >= left_column_right_edge, "panel's left edge clears the party column (got x=%f)" % panel.position.x)
	_check(panel.position.x + panel.size.x <= enemy_column_left_edge, "panel's right edge clears the enemy column (got right=%f)" % (panel.position.x + panel.size.x))
	_check(panel.size.x < 1600.0 and panel.size.y < 900.0, "panel is NOT literally full-screen (got %s)" % panel.size)

	var style: StyleBox = panel.get_theme_stylebox("panel")
	_check(style is StyleBoxFlat, "has an explicit StyleBoxFlat background override (not the theme default)")
	if style is StyleBoxFlat:
		_check((style as StyleBoxFlat).bg_color.a >= 0.95, "background is opaque (alpha >= 0.95, got %f)" % (style as StyleBoxFlat).bg_color.a)

	# Layout regression (review fix 2026-08-01): _end_early_button ("Bank Result") originally sat
	# at (380,402), which overlapped _status_label (60,410)-(860,440) — the status text rendered
	# directly over the button. Moved to the same row as _spin_button/_payline_preview_button
	# (740,350), using the panel's spare width (920 wide; that row's other two buttons only span
	# to x=720). Explicitly check every pair of the panel's static Control children never
	# intersects, so a future coordinate tweak can't silently reintroduce an overlap.
	var named_rects: Dictionary = {
		"_spin_button": Rect2(panel._spin_button.position, panel._spin_button.custom_minimum_size),
		"_end_early_button": Rect2(panel._end_early_button.position, panel._end_early_button.custom_minimum_size),
		"_payline_preview_button": Rect2(panel._payline_preview_button.position, panel._payline_preview_button.custom_minimum_size),
		"_status_label": Rect2(panel._status_label.position, panel._status_label.custom_minimum_size),
		"_tally_label": Rect2(panel._tally_label.position, panel._tally_label.custom_minimum_size),
		"_continue_button": Rect2(panel._continue_button.position, panel._continue_button.custom_minimum_size),
		"_legend_label": Rect2(panel._legend_label.position, panel._legend_label.custom_minimum_size),
	}
	var names: Array = named_rects.keys()
	for i: int in range(names.size()):
		for j: int in range(i + 1, names.size()):
			var name_a: String = names[i]
			var name_b: String = names[j]
			var overlaps: bool = (named_rects[name_a] as Rect2).intersects(named_rects[name_b] as Rect2)
			_check(not overlaps, "%s does not overlap %s" % [name_a, name_b])

	print(("TEAM UP PANEL CENTER BAND TEST PASSED" if _failures == 0 else "TEAM UP PANEL CENTER BAND TEST FAILED: %d" % _failures))
	quit(_failures)
