class_name DialogueBox
extends Panel

## Line-by-line dialogue UI (spec §6). Built entirely in code (matches
## combat/ui/ability_menu_panel.gd's convention) — construction lives in _init(), not
## _ready(), so the box works whether or not it's ever added to a live scene tree
## (required for headless testing, same reasoning as AbilityMenuPanel).

signal closed

var _dialogue_set: DialogueSet
var _index: int = 0
var _name_label: Label
var _text_label: Label

## True once `index` has advanced past the set's last line. Pure/static so it's
## unit-testable without an instance.
static func is_finished(dialogue_set: DialogueSet, index: int) -> bool:
	return index >= dialogue_set.line_count()

## The line at `index`. Callers must check is_finished() first — this does not bounds-check.
static func line_at(dialogue_set: DialogueSet, index: int) -> DialogueLine:
	return dialogue_set.lines[index]

func _init() -> void:
	_name_label = Label.new()
	_name_label.position = Vector2(16, 8)
	add_child(_name_label)

	_text_label = Label.new()
	_text_label.position = Vector2(16, 32)
	_text_label.custom_minimum_size = Vector2(560, 60)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_text_label)

	hide()

func open(dialogue_set: DialogueSet) -> void:
	_dialogue_set = dialogue_set
	_index = 0
	_render_current()
	show()

func advance() -> void:
	_index += 1
	if is_finished(_dialogue_set, _index):
		close()
	else:
		_render_current()

func close() -> void:
	hide()
	closed.emit()

func is_open() -> bool:
	return visible

func _render_current() -> void:
	var line: DialogueLine = line_at(_dialogue_set, _index)
	_name_label.text = line.speaker_name
	_text_label.text = line.text

## --- Headless test hooks (mirrors AbilityMenuPanel's press_row_for_test convention) ---

func current_speaker_for_test() -> String:
	return _name_label.text

func current_text_for_test() -> String:
	return _text_label.text

func advance_for_test() -> void:
	advance()
