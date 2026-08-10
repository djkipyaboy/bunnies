extends SceneTree

## Headless test: opening the Event Log or Professions panel completes the matching tutorial
## objective (2026-08-10 quest-popups-and-tutorial-wiring plan Task 11). town_demo only — the same
## wiring pattern is applied identically to overworld_demo/dungeon_demo, covered by their own
## existing panel-toggle smoke tests continuing to pass (re-run in Step 4).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory

	_check(not inv.is_objective_complete(&"tutorial", &"open_event_log"), "open_event_log isn't complete yet")
	scene._event_log_panel.visible = false   # ensure the next toggle is an OPEN transition
	var event := InputEventAction.new()
	event.action = &"toggle_event_log"
	event.pressed = true
	scene._unhandled_input(event)
	_check(scene._event_log_panel.visible, "the Event Log opened")
	_check(inv.is_objective_complete(&"tutorial", &"open_event_log"), "opening the Event Log completes open_event_log")

	_check(not inv.is_objective_complete(&"tutorial", &"open_professions"), "open_professions isn't complete yet")
	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "Professions opened")
	_check(inv.is_objective_complete(&"tutorial", &"open_professions"), "opening Professions completes open_professions")

	quit()
