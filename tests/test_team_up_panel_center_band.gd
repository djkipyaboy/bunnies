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

	print(("TEAM UP PANEL CENTER BAND TEST PASSED" if _failures == 0 else "TEAM UP PANEL CENTER BAND TEST FAILED: %d" % _failures))
	quit(_failures)
