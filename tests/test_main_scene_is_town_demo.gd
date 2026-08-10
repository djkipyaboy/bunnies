extends SceneTree

## Headless test locking in the project's boot scene (2026-08-10): an exported build must land in
## town_demo.tscn, not combat.tscn, or a fresh export never reaches the tutorial's auto-start
## (flagged by the quest-popups-and-tutorial-wiring final review — town_demo already has its own
## fresh-boot party-seed fallback via InventoryDemoSetup.seed_demo_party() for exactly this case).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_scene == "res://world/town_demo.tscn", "main_scene is town_demo.tscn (got: %s)" % main_scene)

	print(("MAIN SCENE IS TOWN DEMO TEST PASSED" if _failures == 0 else "MAIN SCENE IS TOWN DEMO TEST FAILED: %d" % _failures))
	quit(_failures)
