class_name CharacterCreationScreen
extends Control

## The pre-story character creation screen (spec 2026-08-13-character-creation-design.md). Species
## -> Class(tentative) -> Background -> Name, free back/forth between steps, a persistent reel
## preview, then Finalize builds a real Combatant and emits character_created. Built entirely in
## code (only the root Control lives in character_creation_screen.tscn), matching this project's
## InventoryMenuPanel/ProfessionsMenuPanel/TalentMenuPanel convention.
##
## Out of scope here (spec, "Explicitly not built here"): the start-menu entry point that launches
## this screen, and the Class Trial & Lock-In mechanic that later locks class_is_locked -- this
## screen only reserves that field and leaves it false.

signal character_created(pc: Combatant)

const STEP_IDS: Array[StringName] = [&"species", &"class", &"background", &"name"]

var draft: CharacterCreationDraft = CharacterCreationDraft.new()
var _step_index: int = 0

var _species_step: SpeciesStep
var _class_step: ClassStep
var _background_step: BackgroundStep
var _name_step: NameStep
var _reel_preview: ReelPreviewPanel
var _back_button: Button
var _next_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_species_step = SpeciesStep.new()
	_species_step.selected.connect(_on_species_selected)
	_species_step.position = Vector2(24, 24)
	add_child(_species_step)

	_class_step = ClassStep.new()
	_class_step.selected.connect(_on_class_selected)
	_class_step.position = Vector2(24, 24)
	add_child(_class_step)

	_background_step = BackgroundStep.new()
	_background_step.selected.connect(_on_background_selected)
	_background_step.position = Vector2(24, 24)
	add_child(_background_step)

	_name_step = NameStep.new()
	_name_step.name_changed.connect(_on_name_changed)
	_name_step.position = Vector2(24, 24)
	add_child(_name_step)

	_reel_preview = ReelPreviewPanel.new()
	_reel_preview.position = Vector2(400, 24)
	_reel_preview.custom_minimum_size = Vector2(300, 400)
	add_child(_reel_preview)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(_on_back_pressed)
	_back_button.position = Vector2(24, 440)
	add_child(_back_button)

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.pressed.connect(_on_next_pressed)
	_next_button.position = Vector2(120, 440)
	add_child(_next_button)

	_rebuild()

func _rebuild() -> void:
	_species_step.visible = _step_index == 0
	_class_step.visible = _step_index == 1
	_background_step.visible = _step_index == 2
	_name_step.visible = _step_index == 3
	_back_button.visible = _step_index > 0
	_next_button.text = "Finalize" if _step_index == STEP_IDS.size() - 1 else "Next"
	_next_button.disabled = not _current_step_complete()
	_reel_preview.refresh(draft)

func _current_step_complete() -> bool:
	match STEP_IDS[_step_index]:
		&"species": return draft.has_heritage()
		&"class": return draft.has_class()
		&"background": return draft.has_background()
		&"name": return draft.is_name_valid()
		_: return false

func _on_species_selected(id: StringName) -> void:
	draft.heritage_id = id
	_rebuild()

func _on_class_selected(id: StringName) -> void:
	draft.class_id = id
	_rebuild()

func _on_background_selected(id: StringName) -> void:
	draft.background_id = id
	_rebuild()

func _on_name_changed(new_name: String) -> void:
	draft.character_name = new_name
	_rebuild()

func _on_back_pressed() -> void:
	if _step_index > 0:
		_step_index -= 1
		_rebuild()

func _on_next_pressed() -> void:
	if not _current_step_complete():
		return
	if _step_index == STEP_IDS.size() - 1:
		character_created.emit(_build_pc())
	else:
		_step_index += 1
		_rebuild()

## Builds the real PC Combatant from the completed draft: the chosen Heritage's passive is layered
## onto the tentative CharacterClass's base_stats BEFORE build_combatant() runs, so the bump flows
## through build_combatant()'s own single apply_stats()/apply_luck()/start_combat() sequence
## (apply_luck() is explicitly non-idempotent -- see combat/combatant.gd -- so it must only run
## once). The chosen Background's signature face is then inserted into the first weapon reel's
## strip ("the signature face literally appears on the strip" -- design bible §5).
func _build_pc() -> Combatant:
	var character_class: CharacterClass = ClassLibrary.make(draft.class_id)
	var heritage: Heritage = HeritageLibrary.make(draft.heritage_id)
	heritage.apply_passive(character_class.base_stats)
	var pc: Combatant = character_class.build_combatant(true)
	pc.display_name = draft.character_name.strip_edges()
	pc.heritage = heritage
	pc.background = BackgroundLibrary.make(draft.background_id)
	pc.weapon.reels[0].faces.append(pc.background.signature_face)
	pc.class_is_locked = false
	return pc

# --- headless test hooks ---

func current_step_for_test() -> StringName:
	return STEP_IDS[_step_index]

func select_species_for_test(id: StringName) -> void:
	_species_step.select_for_test(id)

func select_class_for_test(id: StringName) -> void:
	_class_step.select_for_test(id)

func select_background_for_test(id: StringName) -> void:
	_background_step.select_for_test(id)

func enter_name_for_test(new_name: String) -> void:
	_name_step.enter_name_for_test(new_name)

func press_next_for_test() -> void:
	_next_button.pressed.emit()

func press_back_for_test() -> void:
	_back_button.pressed.emit()

func can_advance_for_test() -> bool:
	return not _next_button.disabled

func reel_preview_text_for_test() -> String:
	return _reel_preview.text_for_test()
