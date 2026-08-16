# tests/test_overworld_demo_escape_close.gd
extends SceneTree

## Headless test for the 2026-08-15 playtester note, overworld_demo.gd's half — mirrors
## test_town_demo_escape_close.gd exactly for the panel set this scene has: Escape closes a plain
## toggle panel and leaves the Event Log alone; the Event Log itself now defaults to visible,
## anchored bottom-right of the 1600x900 viewport.

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
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	# --- Event Log defaults to visible, anchored bottom-right of the 1600x900 viewport ---
	_check(demo._event_log_panel.visible, "the Event Log starts visible by default")
	_check(demo._event_log_panel.position == Vector2(1148, 620),
		"the Event Log is positioned in the bottom-right corner (1600-432-20, 900-260-20)")

	# --- Escape closes a plain toggle panel (Talents) when nothing else is blocking ---
	demo._toggle_talents()
	_check(demo._talent_panel.visible, "Talents opened via _toggle_talents()")
	demo._unhandled_input(_escape_event())
	_check(not demo._talent_panel.visible, "Escape closed the open Talents panel")
	_check(not demo._pc.movement_paused_for_test(), "Escape-closing Talents resumes movement")

	# --- Escape does NOT touch the Event Log (non-modal by design) ---
	demo._unhandled_input(_escape_event())
	_check(demo._event_log_panel.visible, "Escape with no other panel open leaves the Event Log untouched")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	print(("OVERWORLD DEMO ESCAPE CLOSE TEST PASSED" if _failures == 0 else "OVERWORLD DEMO ESCAPE CLOSE TEST FAILED: %d" % _failures))
	quit(_failures)
