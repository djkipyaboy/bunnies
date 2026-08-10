extends SceneTree

## Headless smoke test: Quest Log opens/closes in dungeon_demo.tscn (2026-08-10 quest-system-and-
## tutorial design §4), mirrors test_overworld_demo_professions.gd.

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var scene: Node = load("res://world/dungeon_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(scene._quest_log_panel != null, "dungeon_demo builds a QuestLogPanel")
	_check(not scene._quest_log_panel.is_open(), "Quest Log starts closed")

	scene._toggle_quest_log()
	_check(scene._quest_log_panel.is_open(), "_toggle_quest_log() opens the panel")
	_check(scene._pc.movement_paused_for_test(), "opening the Quest Log pauses PC movement")

	scene._toggle_quest_log()
	_check(not scene._quest_log_panel.is_open(), "_toggle_quest_log() again closes the panel")
	_check(not scene._pc.movement_paused_for_test(), "closing the Quest Log resumes PC movement")

	scene._toggle_quest_log()
	scene._toggle_professions()
	_check(scene._quest_log_panel.is_open(), "opening Professions while the Quest Log is open is blocked")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	quit(_failures)
