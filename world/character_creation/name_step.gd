class_name NameStep
extends Control

## Name-entry step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md) --
## always last, per the player's explicit preference. Validation (length cap, allowed characters)
## lives on CharacterCreationDraft; this panel just surfaces it inline, never as a modal, and only
## once the player has actually typed something (an empty field shows no error, just a disabled
## Next button -- CharacterCreationScreen owns that gating).

signal name_changed(new_name: String)

var _line_edit: LineEdit
var _error_label: Label
var _validity_check: CharacterCreationDraft = CharacterCreationDraft.new()

func _init() -> void:
	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "Enter your name"
	# Playtest-found fix (2026-08-13): with no explicit width, this defaulted to a tiny box that
	# clipped even the placeholder text ("Enter y...").
	_line_edit.custom_minimum_size = Vector2(400.0, 32.0)
	_line_edit.text_changed.connect(_on_text_changed)
	add_child(_line_edit)

	_error_label = Label.new()
	_error_label.position = Vector2(0.0, 32.0)
	_error_label.text = "Name must be 1-20 characters, letters/spaces/'/- only"
	_error_label.visible = false
	add_child(_error_label)

func _on_text_changed(new_text: String) -> void:
	_validity_check.character_name = new_text
	_error_label.visible = not new_text.is_empty() and not _validity_check.is_name_valid()
	name_changed.emit(new_text)

func enter_name_for_test(new_name: String) -> void:
	_line_edit.text = new_name
	_on_text_changed(new_name)

func error_visible_for_test() -> bool:
	return _error_label.visible

func text_for_test() -> String:
	return _line_edit.text
