# tests/test_dungeon_demo_escape_close.gd
extends SceneTree

## Headless test for the 2026-08-15 playtester note, dungeon_demo.gd's half — mirrors
## test_town_demo_escape_close.gd for the panel set this scene has (no dialogue/board/vendor/shop/
## gathering panels here). dungeon_demo.gd already builds its own EventLogPanel (added by a
## concurrent tutorial-objective fix), so the same default-visible/bottom-right treatment applies
## here too for consistency with town/overworld.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _escape_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event

func _initialize() -> void:
	var scene: PackedScene = load("res://world/dungeon_demo.tscn")
	var dungeon: DungeonDemo = scene.instantiate() as DungeonDemo
	get_root().add_child(dungeon)
	await process_frame
	await process_frame

	# --- Event Log defaults to visible, anchored bottom-right of the 1600x900 viewport ---
	_check(dungeon._event_log_panel.visible, "the Event Log starts visible by default")
	_check(dungeon._event_log_panel.position == Vector2(1148, 620),
		"the Event Log is positioned in the bottom-right corner (1600-432-20, 900-260-20)")

	# --- Escape closes a plain toggle panel (Professions) when nothing else is blocking ---
	dungeon._toggle_professions()
	_check(dungeon._professions_panel.is_open(), "Professions opened via _toggle_professions()")
	dungeon._unhandled_input(_escape_event())
	_check(not dungeon._professions_panel.is_open(), "Escape closed the open Professions panel")
	_check(not dungeon._pc.movement_paused_for_test(), "Escape-closing Professions resumes movement")

	# --- Escape does NOT touch the Event Log (non-modal by design) ---
	dungeon._unhandled_input(_escape_event())
	_check(dungeon._event_log_panel.visible, "Escape with no other panel open leaves the Event Log untouched")

	dungeon.queue_free()
	await process_frame
	print(("DUNGEON DEMO ESCAPE CLOSE TEST PASSED" if _failures == 0 else "DUNGEON DEMO ESCAPE CLOSE TEST FAILED: %d" % _failures))
	quit(_failures)
