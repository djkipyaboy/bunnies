extends SceneTree

## Headless test for the 2026-07-23 playtest fix: CagedCat (Whiskers) previously had NO visual
## indicator at all — a placeholder tint + floating proximity label, mirroring
## GroundItemPickup's exact convention, so its location on the floor is visible before the player
## walks into its interact radius.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var cat := CagedCat.new()
	cat.party_inventory = PartyInventory.new()
	root.add_child(cat)
	await process_frame
	await process_frame

	var glow: ColorRect = null
	for child in cat.get_children():
		if child is ColorRect:
			glow = child
	_check(glow != null, "CagedCat builds a placeholder ColorRect glow")

	_check(cat._proximity_label != null, "CagedCat builds a floating proximity label")
	_check(not cat._proximity_label.visible, "the proximity label starts hidden")

	cat.set_highlighted(true)
	_check(cat._proximity_label.visible, "set_highlighted(true) shows the proximity label")
	cat.set_highlighted(false)
	_check(not cat._proximity_label.visible, "set_highlighted(false) hides the proximity label again")

	cat.free()
	print(("CAGED CAT VISUAL INDICATOR TEST PASSED" if _failures == 0 else "CAGED CAT VISUAL INDICATOR TEST FAILED: %d" % _failures))
	quit(_failures)
