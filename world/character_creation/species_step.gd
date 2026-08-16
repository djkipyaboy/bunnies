class_name SpeciesStep
extends Control

## Species-picker step of CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## One button per HeritageLibrary entry; placeholder visuals (plain labeled buttons), matching the
## project's placeholder-rectangle art direction. Buttons are built in _init(), not _ready(), so
## this step is fully testable via .new() alone -- no scene-tree insertion required, matching this
## project's InventoryMenuPanel/ProfessionsMenuPanel/TalentMenuPanel convention.
##
## Playtester ask (2026-08-15): explain what each stat actually DOES on this screen, not just the
## flat "+1 X" already on each button. An info Label below the button list always shows a glossary
## of all six stats (via StatCatalog, itself sourced from Stats.gd's own docstring -- no new/
## invented copy), and calls out the selected Heritage's own boosted stat first.
##
## Playtester ask (2026-08-15): show *something* visual per species on selection so a playtest
## doesn't feel like an unbroken wall of text -- explicitly NOT asking for real art yet. A
## ColorRect swatch (one flat color per species id) plus an explicit "not final" caption, matching
## this project's existing placeholder-rectangle art direction (CLAUDE.md 1) rather than sourcing
## or faking a real image.

const BUTTON_H: float = 32.0

## Playtest-found fix (2026-08-13): with no explicit width, each button sized itself tightly
## around its own text -- cramped and unreadable. The screen is 1600px wide with room to spare, so
## give every option a real, generous width instead of letting it wrap/clip.
const BUTTON_W: float = 900.0

## Playtest-found fix (2026-08-15): the info label had no bound on its rendered height, so long
## glossary text pushed past its box and overlapped the Back/Next buttons below it (now at
## CharacterCreationScreen y=820). A ScrollContainer clips it to a fixed height (scrollable)
## regardless of how long the text gets; sized to fit under 9 stacked species buttons with margin.
const INFO_H: float = 450.0

const PORTRAIT_SIZE: float = 120.0

## One flat color per species id -- explicitly a placeholder, not real art (see class doc comment).
const PORTRAIT_COLORS: Dictionary = {
	&"hare": Color(0.85, 0.75, 0.55),
	&"otter": Color(0.45, 0.55, 0.65),
	&"badger": Color(0.35, 0.35, 0.4),
	&"mouse": Color(0.75, 0.65, 0.6),
	&"frog": Color(0.4, 0.65, 0.35),
	&"turtle": Color(0.3, 0.55, 0.45),
	&"fox": Color(0.8, 0.45, 0.25),
	&"weasel": Color(0.7, 0.7, 0.4),
	&"wildcat": Color(0.55, 0.3, 0.5),
}

signal selected(id: StringName)

var _buttons: Dictionary = {}   # StringName -> Button
var _selected_id: StringName = &""
var _info_label: Label
var _portrait: ColorRect

func _init() -> void:
	var y: float = 0.0
	for id: StringName in HeritageLibrary.IDS:
		var heritage: Heritage = HeritageLibrary.make(id)
		var btn: Button = Button.new()
		btn.text = "%s (%s)" % [heritage.species_name, heritage.passive_description]
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

	var content: VBoxContainer = VBoxContainer.new()
	content.custom_minimum_size = Vector2(BUTTON_W - 24.0, 0.0)
	scroll.add_child(content)

	_portrait = ColorRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.color = PORTRAIT_COLORS[HeritageLibrary.IDS[0]]
	content.add_child(_portrait)

	var portrait_caption: Label = Label.new()
	portrait_caption.text = "Art placeholder -- not final."
	portrait_caption.add_theme_font_size_override("font_size", 11)
	content.add_child(portrait_caption)

	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(BUTTON_W - 24.0, 0.0)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.text = _stat_glossary_text()
	content.add_child(_info_label)

func _on_pressed(id: StringName) -> void:
	_selected_id = id
	for key: StringName in _buttons:
		var btn: Button = _buttons[key]
		btn.modulate = Color(0.6, 1.0, 0.6) if key == id else Color.WHITE
	_info_label.text = _build_info_text(id)
	_portrait.color = PORTRAIT_COLORS[id]
	selected.emit(id)

## Composes the info-panel text for [param id]'s Heritage: its species/passive line, the boosted
## stat's own description called out first, then the full six-stat glossary for reference.
func _build_info_text(id: StringName) -> String:
	var heritage: Heritage = HeritageLibrary.make(id)
	var lines: PackedStringArray = []
	lines.append("%s — %s" % [heritage.species_name, heritage.passive_description])
	lines.append("%s: %s" % [StatCatalog.display_name(heritage.passive_stat), StatCatalog.description(heritage.passive_stat)])
	lines.append(_stat_glossary_text())
	return "\n".join(lines)

## One line per stat, all six, in StatCatalog.ORDER -- always visible so the player can compare
## every species' passive against what it actually affects before picking.
func _stat_glossary_text() -> String:
	var lines: PackedStringArray = ["What each stat does:"]
	for stat: StringName in StatCatalog.ORDER:
		lines.append("%s: %s" % [StatCatalog.display_name(stat), StatCatalog.description(stat)])
	return "\n".join(lines)

func select_for_test(id: StringName) -> void:
	(_buttons[id] as Button).pressed.emit()

func selected_id_for_test() -> StringName:
	return _selected_id

func info_text_for_test() -> String:
	return _info_label.text
