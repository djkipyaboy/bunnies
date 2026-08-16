class_name ClassStep
extends Control

## Class-picker step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## The pick made here is TENTATIVE -- a future Class Trial & Lock-In mechanic lets the player try
## other classes post-tutorial before it becomes permanent (Combatant.class_is_locked, Task 3).
## One button per ClassLibrary entry; placeholder visuals; built in _init() like SpeciesStep.
##
## Playtester ask (2026-08-15): explain each class's abilities/lore before picking. An info Label
## below the button list shows the selected class's role/weapon/reel line plus its base ability,
## L5 passive, Ultimate, and L5/L7/L9 extra abilities -- all pulled from AbilityCatalog/
## UltimateCatalog/CharacterClass (the project's existing single sources of truth for that copy;
## combat.gd's own ability/Ultimate tooltips read from the same catalogs), never duplicated here.

const BUTTON_H: float = 32.0

## Playtest-found fix (2026-08-13): with no explicit width, each button sized itself tightly
## around its own text -- cramped and unreadable. The screen is 1600px wide with room to spare, so
## give every option a real, generous width instead of letting it wrap/clip.
const BUTTON_W: float = 900.0

## Playtest-found fix (2026-08-15): the info label had no bound on its rendered height, so a
## class with several extra abilities pushed past its box and overlapped the Back/Next buttons
## below it (now at CharacterCreationScreen y=820). A ScrollContainer clips it to a fixed height
## (scrollable) regardless of text length; sized to fit under 7 stacked class buttons with margin.
const INFO_H: float = 520.0
const DEFAULT_INFO_TEXT: String = "Select a class to see its abilities and details."

signal selected(id: StringName)

var _buttons: Dictionary = {}   # StringName -> Button
var _selected_id: StringName = &""
var _info_label: Label

func _init() -> void:
	var y: float = 0.0
	for id: StringName in ClassLibrary.IDS:
		var character_class: CharacterClass = ClassLibrary.make(id)
		var btn: Button = Button.new()
		btn.text = "%s (%d reels)" % [String(id).capitalize(), character_class.reel_count]
		btn.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
		btn.position = Vector2(0.0, y)
		btn.pressed.connect(_on_pressed.bind(id))
		add_child(btn)
		_buttons[id] = btn
		y += BUTTON_H

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(0.0, y + 8.0)
	scroll.custom_minimum_size = Vector2(BUTTON_W, INFO_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(BUTTON_W - 24.0, 0.0)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.text = DEFAULT_INFO_TEXT
	scroll.add_child(_info_label)

func _on_pressed(id: StringName) -> void:
	_selected_id = id
	for key: StringName in _buttons:
		var btn: Button = _buttons[key]
		btn.modulate = Color(0.6, 1.0, 0.6) if key == id else Color.WHITE
	_info_label.text = _build_info_text(id)
	selected.emit(id)

## Composes the info-panel text for [param id]'s class: role/weapon/reel summary, base ability,
## L5 passive (if any), Ultimate, and every L5/L7/L9 extra ability -- reusing AbilityCatalog/
## UltimateCatalog copy rather than re-authoring it here.
func _build_info_text(id: StringName) -> String:
	var cc: CharacterClass = ClassLibrary.make(id)
	var lines: PackedStringArray = []
	lines.append("%s — %s" % [cc.display_name, RoleVisuals.label(cc.combat_role).capitalize()])
	lines.append("%s · %d reels · %s" % [TypeVisuals.type_name(cc.weapon_type), cc.reel_count, cc.weapon_display_name])
	lines.append("Ability — %s: %s" % [AbilityCatalog.display_name(cc.ability_id), AbilityCatalog.description(cc.ability_id)])
	if cc.passive_ability_id != &"":
		lines.append("Passive — %s: %s" % [AbilityCatalog.display_name(cc.passive_ability_id), AbilityCatalog.description(cc.passive_ability_id)])
	lines.append("Ultimate — %s: %s" % [UltimateCatalog.display_name(cc.ultimate_id), UltimateCatalog.description(cc.ultimate_id)])
	for extra: AbilityDef in cc.extra_abilities:
		lines.append("L%d — %s: %s" % [extra.unlock_level, AbilityCatalog.display_name(extra.id), AbilityCatalog.description(extra.id)])
	return "\n".join(lines)

func select_for_test(id: StringName) -> void:
	(_buttons[id] as Button).pressed.emit()

func selected_id_for_test() -> StringName:
	return _selected_id

func info_text_for_test() -> String:
	return _info_label.text
