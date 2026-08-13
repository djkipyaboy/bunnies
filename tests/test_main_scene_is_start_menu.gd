extends SceneTree

## Headless test locking in the project's boot scene (2026-08-13 start-menu spec) -- supersedes the
## 2026-08-10 decision (tests/test_main_scene_is_town_demo.gd, now deleted) that main_scene must be
## town_demo.tscn. A real StartMenu now exists and owns the "New Game" path into town_demo.tscn via
## CharacterCreationScreen + InventoryDemoSetup.seed_demo_party(pc), so the exported build's entry
## point is the start menu, not the town directly.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	_check(main_scene == "res://world/start_menu.tscn", "main_scene is start_menu.tscn (got: %s)" % main_scene)

	print(("MAIN SCENE IS START MENU TEST PASSED" if _failures == 0 else "MAIN SCENE IS START MENU TEST FAILED: %d" % _failures))
	quit(_failures)
