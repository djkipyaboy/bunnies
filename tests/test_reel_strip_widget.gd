extends SceneTree

## ReelStripWidget: shared 3-cell (prev/current/next) reel display (2026-08-02
## gathering-playtest-fixes spec section 1). Dumb view -- no reel/model state of its own; reused by
## both ForagingPanel (a presentation-only spin) and FishingPanel (a real rotating reel).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var widget: ReelStripWidget = ReelStripWidget.new()
	get_root().add_child(widget)
	await process_frame

	widget.set_cells("Fail", "Success", "Critical", false, false, true)
	_check(widget.cell_text_for_test(&"prev") == "Fail", "prev cell text set correctly")
	_check(widget.cell_text_for_test(&"current") == "Success", "current cell text set correctly")
	_check(widget.cell_text_for_test(&"next") == "Critical", "next cell text set correctly")
	_check(widget.cell_font_size_for_test(&"prev") == ReelStripWidget.NORMAL_FONT_SIZE, "prev cell renders at normal size when not marked small")
	_check(widget.cell_font_size_for_test(&"current") == ReelStripWidget.NORMAL_FONT_SIZE, "current cell renders at normal size when not marked small")
	_check(widget.cell_font_size_for_test(&"next") == ReelStripWidget.SMALL_FONT_SIZE, "next cell renders at the small size when marked small")

	# Prove the three cells are independently settable -- marking ONLY the current cell small
	# doesn't affect prev/next, proving the flags aren't coupled to each other.
	widget.set_cells("Meager", "Bumper Crop", "Modest", false, true, false)
	_check(widget.cell_font_size_for_test(&"prev") == ReelStripWidget.NORMAL_FONT_SIZE, "prev cell stays normal size when only current is marked small")
	_check(widget.cell_font_size_for_test(&"current") == ReelStripWidget.SMALL_FONT_SIZE, "current cell renders small when marked small")
	_check(widget.cell_font_size_for_test(&"next") == ReelStripWidget.NORMAL_FONT_SIZE, "next cell stays normal size when only current is marked small")
	_check(widget.cell_text_for_test(&"current") == "Bumper Crop", "text updates correctly on a second set_cells() call")

	# --- Per-cell color ---
	widget.set_cells("Fail", "Success", "Critical", false, false, false, Color.RED, Color.GREEN, Color.BLUE)
	_check(widget.cell_color_for_test(&"prev") == Color.RED, "prev cell color set correctly")
	_check(widget.cell_color_for_test(&"current") == Color.GREEN, "current cell color set correctly")
	_check(widget.cell_color_for_test(&"next") == Color.BLUE, "next cell color set correctly")

	# A call with no color arguments defaults every cell to plain white (matches the pre-color
	# appearance -- no caller is forced to opt in).
	widget.set_cells("Meager", "Modest", "Bountiful")
	_check(widget.cell_color_for_test(&"prev") == Color.WHITE, "prev cell defaults to white when no color is given")
	_check(widget.cell_color_for_test(&"current") == Color.WHITE, "current cell defaults to white when no color is given (no more hardcoded gold tint)")
	_check(widget.cell_color_for_test(&"next") == Color.WHITE, "next cell defaults to white when no color is given")

	# --- clip_text structural backstop (final-review finding, 2026-08-02) ---
	# Set unconditionally regardless of caller/text, so a long label from any future caller can't
	# visually bleed into the next reel column even if that caller forgets to keep its own text short.
	_check(widget.cell_clips_text_for_test(&"prev"), "prev cell clips text")
	_check(widget.cell_clips_text_for_test(&"current"), "current cell clips text")
	_check(widget.cell_clips_text_for_test(&"next"), "next cell clips text")

	# Task 4 (2026-08-07 professions-playtest-fixes): small arrow markers flank the CENTER cell so
	# every reel-based mini-game shows which slot actually counts, without needing per-mini-game UI.
	_check(widget.left_arrow_text_for_test() == "▶", "left arrow points inward at the center cell")
	_check(widget.right_arrow_text_for_test() == "◀", "right arrow points inward at the center cell")
	_check(widget.arrows_flank_center_cell_for_test(), "both arrows sit inside the strip's own cell column, near its left/right edges, at the center cell's vertical position")

	# Task 4 fix round 1: prove two adjacent columns at the real STRIP_GAP=100 spacing used by
	# FishingPanel/TemperingReelsPanel/SecondHelpingPanel don't have overlapping arrow footprints --
	# this is the actual scenario the original outside-the-column placement broke.
	var col_a := ReelStripWidget.new()
	var col_b := ReelStripWidget.new()
	get_root().add_child(col_a)
	get_root().add_child(col_b)
	await process_frame
	col_a.position = Vector2(0.0, 0.0)
	col_b.position = Vector2(100.0, 0.0)
	var col_a_right_arrow_max_x: float = col_a.position.x + col_a.right_arrow_x_for_test() + ReelStripWidget.ARROW_W
	var col_b_left_arrow_min_x: float = col_b.position.x + col_b.left_arrow_x_for_test()
	_check(col_a_right_arrow_max_x <= col_b_left_arrow_min_x, "adjacent columns at real STRIP_GAP=100 spacing have non-overlapping arrow footprints (col A right arrow ends at %.1f, col B left arrow starts at %.1f)" % [col_a_right_arrow_max_x, col_b_left_arrow_min_x])
	col_a.free()
	col_b.free()

	widget.free()
	quit()
