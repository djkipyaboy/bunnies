extends SceneTree

## Headless test for WorldTooltip (Plan 3, world hover tooltips) — mirrors InteractPrompt's
## hidden-by-default / show_*/hide_* shape (tests/test_interact_prompt.gd if present, or the class's
## own doc comment).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var tooltip := WorldTooltip.new()
	_check(not tooltip.visible, "hidden by default")

	tooltip.show_tooltip("General Store — spend Amber on gear, weapons, and consumables.")
	_check(tooltip.visible, "show_tooltip makes it visible")
	_check(tooltip.text == "General Store — spend Amber on gear, weapons, and consumables.", "show_tooltip sets the label text")

	tooltip.hide_tooltip()
	_check(not tooltip.visible, "hide_tooltip hides it again")

	tooltip.free()
	print(("WORLD TOOLTIP TEST PASSED" if _failures == 0 else "WORLD TOOLTIP TEST FAILED: %d" % _failures))
	quit(_failures)
