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

	widget.free()
	quit()
