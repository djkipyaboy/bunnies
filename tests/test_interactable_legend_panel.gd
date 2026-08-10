# tests/test_interactable_legend_panel.gd
extends SceneTree

## Headless test for InteractableLegendPanel (2026-08-10 quest-system-and-tutorial design §9,
## pulled forward into the quest-popups-and-tutorial-wiring plan's Task 4).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel := InteractableLegendPanel.new()
	_check(not panel.is_open(), "starts closed")
	_check(panel.row_count_for_test() == 6, "has all 6 interactable-type rows (got %d)" % panel.row_count_for_test())
	_check(panel.row_text_for_test(0).contains("Foraging"), "row 0 is Foraging")
	_check(panel.row_text_for_test(2).contains("Enemy"), "row 2 is Enemy")
	_check(panel.row_text_for_test(5).contains("Reward pickup"), "row 5 is Reward pickup")

	panel.open()
	_check(panel.is_open(), "open() opens the panel")
	panel.close()
	_check(not panel.is_open(), "close() closes the panel")

	panel.free()
	print(("INTERACTABLE LEGEND PANEL TEST PASSED" if _failures == 0 else "INTERACTABLE LEGEND PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
