class_name ClassStep
extends Control

## Class-picker step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## The pick made here is TENTATIVE -- a future Class Trial & Lock-In mechanic lets the player try
## other classes post-tutorial before it becomes permanent (Combatant.class_is_locked, Task 3).
## One button per ClassLibrary entry; placeholder visuals; built in _init() like SpeciesStep.

const BUTTON_H: float = 32.0

signal selected(id: StringName)

var _buttons: Dictionary = {}   # StringName -> Button
var _selected_id: StringName = &""

func _init() -> void:
	var y: float = 0.0
	for id: StringName in ClassLibrary.IDS:
		var character_class: CharacterClass = ClassLibrary.make(id)
		var btn: Button = Button.new()
		btn.text = "%s (%d reels)" % [String(id).capitalize(), character_class.reel_count]
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
