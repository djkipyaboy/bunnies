extends SceneTree

## One-off generator for this project's first Input Map actions (2026-07-07-demo-town-prototype-design.md).
## Run once via `--script`; safe to re-run (it clears and rewrites each action's events).

func _add_action(action_name: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		InputMap.action_erase_event(action_name, existing_event)
	for keycode in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action_name, event)
	var events: Array = []
	for event2 in InputMap.action_get_events(action_name):
		events.append(event2)
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": 0.5, "events": events})

func _init() -> void:
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("interact", [KEY_E])
	var save_error: Error = ProjectSettings.save()
	print("input map saved with error code: ", save_error)
	quit()
