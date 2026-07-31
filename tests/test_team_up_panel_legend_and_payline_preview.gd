extends SceneTree

## Headless test: TeamUpPanel gets a symbol legend and a payline-preview cycle toggle — playtest
## 2026-07-31 asked for both ("a Key at the bottom... describes what each reel face does, as well
## as a payline toggle to show players what to be aiming for with their reel face locks").
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_panel_legend_and_payline_preview.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var panel: TeamUpPanel = TeamUpPanel.new()
	root.add_child(panel)  # _ready() must run before we inspect its fields — see
	# tests/test_team_up_panel_center_band.gd's identical established pattern (the brief's own
	# literal test omitted this await and would hang/fail on a null _legend_label without it).
	await process_frame
	await process_frame

	_check(panel._legend_label != null, "a legend label exists")
	var legend_text: String = panel._legend_label.text
	for symbol_name: String in ["Strike", "Mend", "Ward", "Break", "Surge"]:
		_check(legend_text.contains(symbol_name), "legend mentions %s" % symbol_name)

	_check(panel._payline_preview_button != null, "a payline-preview toggle button exists")

	# Open a real round so the grid/minigame exist, then exercise the cycle. TeamUpReel.make_default()
	# is the established test convention (see tests/test_team_up_minigame.gd) — a bare TeamUpReel.new()
	# has no faces and would crash on spin().
	var reels: Array[TeamUpReel] = []
	for i in range(5):
		reels.append(TeamUpReel.make_default([[&"strike", 1]]))
	var config: Dictionary = {"reels": reels, "lock_tokens": 9, "max_spins": 5, "damage_type": null}
	panel.open_for(config, [], [])
	panel._on_spin_pressed()  # populate the grid so there's something to preview lines over

	_check(panel._payline_preview_cells.is_empty(), "no preview highlighted before the toggle is pressed")
	panel._on_payline_preview_pressed()
	_check(not panel._payline_preview_cells.is_empty(), "pressing the toggle highlights one payline's cells")
	var first_cells: Array = panel._payline_preview_cells.duplicate()
	panel._on_payline_preview_pressed()
	_check(panel._payline_preview_cells != first_cells or PaylineLibrary.lines_for(5).size() == 1, "pressing again cycles to a different line (unless there's only one)")

	print(("TEAM UP PANEL LEGEND AND PAYLINE PREVIEW TEST PASSED" if _failures == 0 else "TEAM UP PANEL LEGEND AND PAYLINE PREVIEW TEST FAILED: %d" % _failures))
	quit(_failures)
