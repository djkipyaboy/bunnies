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

	widget.free()
	quit()
