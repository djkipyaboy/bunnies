class_name SpeciesStep
extends Control

## Species-picker step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## One button per HeritageLibrary entry; placeholder visuals (plain labeled buttons), matching the
## project's placeholder-rectangle art direction. Buttons are built in _init(), not _ready(), so
## this step is fully testable via .new() alone -- no scene-tree insertion required, matching this
## project's InventoryMenuPanel/ProfessionsMenuPanel/TalentMenuPanel convention.

const BUTTON_H: float = 32.0

signal selected(id: StringName)

var _buttons: Dictionary = {}   # StringName -> Button
var _selected_id: StringName = &""

func _init() -> void:
	var y: float = 0.0
	for id: StringName in HeritageLibrary.IDS:
		var heritage: Heritage = HeritageLibrary.make(id)
		var btn: Button = Button.new()
		btn.text = "%s (%s)" % [heritage.species_name, heritage.passive_description]
		btn.position = Vector2(0.0, y)
		btn.pressed.connect(_on_pressed.bind(id))
		add_child(btn)
		_buttons[id] = btn
		y += BUTTON_H

func _on_pressed(id: StringName) -> void:
	_selected_id = id
	for key: StringName in _buttons:
		var btn: Button = _buttons[key]
		btn.modulate = Color(0.6, 1.0, 0.6) if key == id else Color.WHITE
	selected.emit(id)

func select_for_test(id: StringName) -> void:
	(_buttons[id] as Button).pressed.emit()

func selected_id_for_test() -> StringName:
	return _selected_id
