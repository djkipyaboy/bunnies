# tests/test_town_demo_escape_close.gd
extends SceneTree

## Headless test for the 2026-08-15 playtester note: every togglable/modal panel should also close
## on Escape (ui_cancel), in addition to its own keybind/close button — EXCEPT the Event Log, which
## is non-modal by design (see EventLogPanel's own doc comment) and must stay untouched by Escape.
## Also covers the paired note: the Event Log now defaults to visible (bottom-right corner of the
## 1600x900 viewport) instead of starting hidden, while staying toggleable via 'L'.
## Synthesizes InputEventAction the same way test_town_demo_quest_popup_guards.gd's 'E'-press
## coverage does, and calls _unhandled_input() directly (this project's headless-test convention for
## exercising a keybind without a live input device).

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
	var scene: PackedScene = load("res://world/town_demo.tscn")
	var town: TownDemo = scene.instantiate() as TownDemo
	root.add_child(town)
	await process_frame
	await process_frame

	# --- Event Log defaults to visible, anchored bottom-right of the 1600x900 viewport ---
	_check(town._event_log_panel.visible, "the Event Log starts visible by default")
	_check(town._event_log_panel.position == Vector2(1148, 620),
		"the Event Log is positioned in the bottom-right corner (1600-432-20, 900-260-20)")

	# --- Escape closes a plain toggle panel (Inventory) when nothing else is blocking ---
	town._toggle_inventory()
	_check(town._inventory_panel.visible, "Inventory opened via _toggle_inventory()")
	town._unhandled_input(_escape_event())
	_check(not town._inventory_panel.visible, "Escape closed the open Inventory panel")
	_check(not town._pc.movement_paused_for_test(), "Escape-closing Inventory resumes movement")

	# --- Escape does NOT touch the Event Log (non-modal by design) ---
	_check(town._event_log_panel.visible, "the Event Log is still visible before the next check")
	town._unhandled_input(_escape_event())
	_check(town._event_log_panel.visible, "Escape with no other panel open leaves the Event Log untouched")

	town._event_log_panel.visible = false
	town._toggle_quest_log()
	_check(town._quest_log_panel.is_open(), "Quest Log opened via _toggle_quest_log()")
	town._unhandled_input(_escape_event())
	_check(not town._quest_log_panel.is_open(), "Escape closed the open Quest Log panel")
	_check(not town._event_log_panel.visible,
		"Escape closing another panel still leaves the Event Log's own visibility untouched")

	# --- Escape closes the linear DialogueBox and resumes movement (mirrors _dialogue_box.close()'s
	# existing `closed` wiring to _on_dialogue_closed()) ---
	var lines: Array[DialogueLine] = [DialogueLine.new()]
	lines[0].speaker_name = "Villager"
	lines[0].text = "Hello there."
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	town._pc.set_movement_paused(true)
	town._dialogue_box.open(dialogue_set)
	_check(town._dialogue_box.is_open(), "DialogueBox opened for the Escape check")
	town._unhandled_input(_escape_event())
	_check(not town._dialogue_box.is_open(), "Escape closed the open DialogueBox")
	_check(not town._pc.movement_paused_for_test(), "Escape-closing the DialogueBox resumes movement")

	town.free()
	print(("TOWN DEMO ESCAPE CLOSE TEST PASSED" if _failures == 0 else "TOWN DEMO ESCAPE CLOSE TEST FAILED: %d" % _failures))
	quit(_failures)
