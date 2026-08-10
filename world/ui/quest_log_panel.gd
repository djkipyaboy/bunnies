# world/ui/quest_log_panel.gd
class_name QuestLogPanel
extends Panel

## Quest Log window (2026-08-10 quest-system-and-tutorial design §4) — a Q-toggled panel listing
## every accepted quest (Active/Completed), with a detail pane showing the selected quest's
## description, objectives, and reward, a Track checkbox (the "untrack" ability), and an Abandon
## button disabled for TUTORIAL-category quests. Built the same code-only-construction way as
## AdventuringBoardPanel: every open_for() call rebuilds rows from scratch.

const PAD: float = 16.0
const ROW_H: float = 24.0
const LIST_W: float = 200.0
const PANEL_W: float = 560.0
const PANEL_H: float = 320.0
const DETAIL_X: float = PAD + LIST_W + PAD

var _party_inventory: PartyInventory
var _selected_quest_id: StringName = &""
var _row_buttons: Dictionary = {}   # StringName -> Button
var _detail_title: Label
var _detail_body: Label
var _track_checkbox: CheckBox
var _abandon_button: Button

func open_for(party_inventory: PartyInventory) -> void:
	_party_inventory = party_inventory
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	_rebuild()
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_row_buttons.clear()

	var active_ids: Array[StringName] = []
	var completed_ids: Array[StringName] = []
	for quest_id: StringName in _party_inventory.accepted_quest_ids:
		if _party_inventory.has_completed_quest(quest_id):
			completed_ids.append(quest_id)
		else:
			active_ids.append(quest_id)

	var y: float = PAD
	var active_header := Label.new()
	active_header.text = "Active"
	active_header.position = Vector2(PAD, y)
	add_child(active_header)
	y += ROW_H
	for quest_id: StringName in active_ids:
		y = _add_row(quest_id, y)

	var completed_header := Label.new()
	completed_header.text = "Completed"
	completed_header.position = Vector2(PAD, y)
	add_child(completed_header)
	y += ROW_H
	for quest_id: StringName in completed_ids:
		y = _add_row(quest_id, y)

	_build_detail_pane()
	if _selected_quest_id != &"" and (active_ids.has(_selected_quest_id) or completed_ids.has(_selected_quest_id)):
		_select_quest(_selected_quest_id)
	elif not active_ids.is_empty():
		_select_quest(active_ids[0])
	elif not completed_ids.is_empty():
		_select_quest(completed_ids[0])

func _add_row(quest_id: StringName, y: float) -> float:
	var quest: Quest = QuestLibrary.get_quest(quest_id)
	if quest == null:
		return y
	var btn := Button.new()
	btn.text = quest.title
	btn.position = Vector2(PAD, y)
	btn.custom_minimum_size = Vector2(LIST_W, ROW_H - 4.0)
	btn.pressed.connect(_select_quest.bind(quest_id))
	add_child(btn)
	_row_buttons[quest_id] = btn
	return y + ROW_H

func _build_detail_pane() -> void:
	_detail_title = Label.new()
	_detail_title.position = Vector2(DETAIL_X, PAD)
	_detail_title.custom_minimum_size = Vector2(PANEL_W - DETAIL_X - PAD, ROW_H)
	add_child(_detail_title)

	_detail_body = Label.new()
	_detail_body.position = Vector2(DETAIL_X, PAD + ROW_H + 4.0)
	_detail_body.custom_minimum_size = Vector2(PANEL_W - DETAIL_X - PAD, PANEL_H - PAD * 2.0 - ROW_H - 40.0)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_detail_body)

	_track_checkbox = CheckBox.new()
	_track_checkbox.text = "Track"
	_track_checkbox.position = Vector2(DETAIL_X, PANEL_H - PAD - ROW_H)
	_track_checkbox.toggled.connect(_on_track_toggled)
	add_child(_track_checkbox)

	_abandon_button = Button.new()
	_abandon_button.text = "Abandon"
	_abandon_button.position = Vector2(DETAIL_X + 100.0, PANEL_H - PAD - ROW_H)
	_abandon_button.custom_minimum_size = Vector2(90.0, ROW_H - 4.0)
	_abandon_button.pressed.connect(_on_abandon_pressed)
	add_child(_abandon_button)

func _select_quest(quest_id: StringName) -> void:
	_selected_quest_id = quest_id
	var quest: Quest = QuestLibrary.get_quest(quest_id)
	if quest == null:
		return
	_detail_title.text = quest.title
	var lines: Array[String] = [quest.description, ""]
	for objective: QuestObjective in quest.objectives:
		var mark: String = "[x]" if _party_inventory.is_objective_complete(quest_id, objective.id) else "[ ]"
		lines.append("%s %s" % [mark, objective.display_text])
	if quest.reward_amber > 0:
		lines.append("")
		lines.append("Reward: %d Amber" % quest.reward_amber)
	_detail_body.text = "\n".join(lines)

	_track_checkbox.set_pressed_no_signal(_party_inventory.is_quest_tracked(quest_id))
	var completed: bool = _party_inventory.has_completed_quest(quest_id)
	_abandon_button.disabled = completed or quest.category == Quest.Category.TUTORIAL
	_abandon_button.visible = not completed

func _on_track_toggled(pressed: bool) -> void:
	_party_inventory.set_quest_tracked(_selected_quest_id, pressed)

## Re-checks category itself rather than trusting only the Abandon button's `disabled` state —
## disabled blocks a real click, but this handler must be safe even if called directly.
func _on_abandon_pressed() -> void:
	var quest: Quest = QuestLibrary.get_quest(_selected_quest_id)
	if quest != null and quest.category == Quest.Category.TUTORIAL:
		return
	_party_inventory.abandon_quest(_selected_quest_id)
	_rebuild()

## --- Headless test hooks (mirrors AdventuringBoardPanel/EventLogPanel's convention) ---

func press_row_for_test(quest_id: StringName) -> void:
	_select_quest(quest_id)

func toggle_track_for_test(pressed: bool) -> void:
	_track_checkbox.button_pressed = pressed
	_on_track_toggled(pressed)

func press_abandon_for_test() -> void:
	_on_abandon_pressed()

func detail_text_for_test() -> String:
	return _detail_body.text

func is_row_present_for_test(quest_id: StringName) -> bool:
	return _row_buttons.has(quest_id)
