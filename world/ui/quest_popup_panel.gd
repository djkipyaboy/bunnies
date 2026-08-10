# world/ui/quest_popup_panel.gd
class_name QuestPopupPanel
extends Panel

## NPC/board accept and turn-in popup (2026-08-10 quest-system-and-tutorial design §6). Built the
## same code-only-construction way as DialogueBox, since DialogueBox itself is strictly linear (no
## buttons). Pure emitter — never touches PartyInventory itself, mirroring AdventuringBoardPanel's
## "emit and let the caller act" convention (see its own party_selection_pressed doc comment).

signal accepted(quest_id: StringName)
signal declined
signal completed(quest_id: StringName)

const PANEL_W: float = 440.0
const PANEL_H: float = 200.0

var _mode: StringName = &""   # &"offer" or &"turn_in"
var _quest_id: StringName = &""
var _title_label: Label
var _body_label: Label
var _primary_button: Button    # Accept (offer) / Complete (turn_in)
var _secondary_button: Button  # Decline (offer only)

func _init() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size

	_title_label = Label.new()
	_title_label.position = Vector2(16, 8)
	add_child(_title_label)

	_body_label = Label.new()
	_body_label.position = Vector2(16, 32)
	_body_label.custom_minimum_size = Vector2(PANEL_W - 32.0, PANEL_H - 90.0)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_body_label)

	_primary_button = Button.new()
	_primary_button.position = Vector2(16, PANEL_H - 40.0)
	_primary_button.custom_minimum_size = Vector2(120.0, 28.0)
	_primary_button.pressed.connect(_on_primary_pressed)
	add_child(_primary_button)

	_secondary_button = Button.new()
	_secondary_button.position = Vector2(150.0, PANEL_H - 40.0)
	_secondary_button.custom_minimum_size = Vector2(120.0, 28.0)
	_secondary_button.pressed.connect(_on_secondary_pressed)
	add_child(_secondary_button)

	hide()

func open_offer(quest: Quest) -> void:
	_mode = &"offer"
	_quest_id = quest.id
	_title_label.text = quest.title
	var lines: Array[String] = [quest.description, ""]
	for objective: QuestObjective in quest.objectives:
		lines.append("- %s" % objective.display_text)
	_body_label.text = "\n".join(lines)
	_primary_button.text = "Accept"
	_secondary_button.visible = true
	_secondary_button.text = "Decline"
	show()

func open_turn_in(quest: Quest) -> void:
	_mode = &"turn_in"
	_quest_id = quest.id
	_title_label.text = quest.title
	var lines: Array[String] = [quest.description]
	if quest.reward_amber > 0:
		lines.append("")
		lines.append("Reward: %d Amber" % quest.reward_amber)
	_body_label.text = "\n".join(lines)
	_primary_button.text = "Complete"
	_secondary_button.visible = false
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _on_primary_pressed() -> void:
	var id: StringName = _quest_id
	var mode: StringName = _mode
	close()
	if mode == &"offer":
		accepted.emit(id)
	else:
		completed.emit(id)

func _on_secondary_pressed() -> void:
	close()
	declined.emit()

## --- Headless test hooks ---

func press_primary_for_test() -> void:
	_on_primary_pressed()

func press_secondary_for_test() -> void:
	_on_secondary_pressed()

func body_text_for_test() -> String:
	return _body_label.text

func mode_for_test() -> StringName:
	return _mode
