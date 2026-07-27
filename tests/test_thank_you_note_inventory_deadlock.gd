extends SceneTree

## Regression for a playtest-reported bug (2026-07-27): opening the Thank You Note's dialogue from
## INSIDE an already-open InventoryMenuPanel used to leave both the panel and the dialogue stuck —
## neither could be closed. Root cause (found by code comparison, not guessed): every OTHER path
## into DialogueBox goes through town_demo.gd's own _on_dialogue_requested()/_on_vendor_talk_pressed(),
## which the input-handling guards were written around (interact/toggle_inventory always assume at
## most ONE of {dialogue open, inventory open} at a time). The old Thank You Note wiring
## (`_inventory_panel.thank_you_note_requested.connect(_dialogue_box.open)`) skipped that entirely
## and opened the DialogueBox directly ON TOP of an already-visible InventoryMenuPanel — a state the
## rest of the input code never anticipated:
## - `_toggle_inventory()` early-returns whenever `_dialogue_box.is_open()`, so 'I' could no longer
##   close the now-stuck-open inventory panel.
## - `_unhandled_input()` early-returns whenever `_inventory_panel.visible`, BEFORE it ever reached
##   the `_dialogue_box.is_open(): _dialogue_box.advance()` branch — so interact could no longer
##   advance/close the dialogue either.
## Fixed by restoring the "at most one modal panel open" invariant instead: a new
## `_on_thank_you_note_requested()` handler hides the inventory panel BEFORE opening the dialogue,
## so the dual-open state this bug depended on can no longer occur.

var _town_instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("ok " + label)
	else:
		_failures += 1
		print("FAIL " + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		var town: TownDemo = _town_instance
		var note := QuestItem.new()
		note.item_id = &"thank_you_note"
		note.display_name = "A Thank You Note"
		town._party_inventory.give_quest_item(note)

		var open_event := InputEventAction.new()
		open_event.action = &"toggle_inventory"
		open_event.pressed = true
		town._unhandled_input(open_event)
		_check(town._inventory_panel.visible, "the inventory panel opens normally")

		town._inventory_panel.switch_tab_for_test(&"quest")
		town._inventory_panel._on_thank_you_note_pressed()

		_check(not town._inventory_panel.visible, "the inventory panel is hidden once the Thank You Note dialogue opens, restoring one-modal-at-a-time")
		_check(town._dialogue_box.is_open(), "the Thank You Note dialogue is open")
		_check(town._pc.movement_paused_for_test(), "PC movement stays paused across the panel-to-dialogue handoff")

		# The interact key must now be able to advance/close the dialogue.
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		town._unhandled_input(interact_event)
		_check(not town._dialogue_box.is_open(), "interact closes the Thank You Note dialogue (it's a single-line DialogueSet)")
		_check(not town._pc.movement_paused_for_test(), "closing the dialogue resumes PC movement")

		# The inventory panel must be freely reopenable afterward — no lingering stuck state.
		town._unhandled_input(open_event)
		_check(town._inventory_panel.visible, "the inventory panel can be freely reopened after the dialogue closes")

		_town_instance.free()

	if _frames >= 3:
		print(("ok thank-you-note-inventory-deadlock regression complete" if _failures == 0 else "FAIL thank-you-note-inventory-deadlock regression: %d failure(s)" % _failures))
		quit(_failures)
		return true
	return false
