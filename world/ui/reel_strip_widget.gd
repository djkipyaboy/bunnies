class_name ReelStripWidget
extends Control

## Displays a 3-cell (previous/current/next) view of a rotating reel column (2026-08-02
## gathering-playtest-fixes spec section 1). Shared by ForagingPanel (a single column, driven by a
## presentation-only spin) and FishingPanel (N columns, driven by the real continuously-rotating
## FishingMinigame). Dumb view -- owns no reel/model state; callers push whatever three strings (and
## which should render smaller) via set_cells().

const CELL_W: float = 90.0
const CELL_H: float = 30.0
const NORMAL_FONT_SIZE: int = 20
const SMALL_FONT_SIZE: int = 11

var _prev_label: Label
var _current_label: Label
var _next_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(CELL_W, CELL_H * 3.0)
	size = custom_minimum_size

	_prev_label = _make_cell_label(0.0)
	add_child(_prev_label)

	_current_label = _make_cell_label(CELL_H)
	add_child(_current_label)

	_next_label = _make_cell_label(CELL_H * 2.0)
	add_child(_next_label)

func _make_cell_label(y: float) -> Label:
	var label := Label.new()
	label.position = Vector2(0.0, y)
	label.custom_minimum_size = Vector2(CELL_W, CELL_H)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

## Updates all three cells at once. [param prev_small]/[param current_small]/[param next_small] are
## a generic "render this cell smaller" flag -- NOT a Fishing-specific "is critical" concept, so
## Foraging (which has no critical tier) can use this widget too. [param prev_color]/
## [param current_color]/[param next_color] default to plain white -- a caller that doesn't pass
## colors gets the same unstyled appearance as before this field existed.
func set_cells(prev_text: String, current_text: String, next_text: String,
		prev_small: bool = false, current_small: bool = false, next_small: bool = false,
		prev_color: Color = Color.WHITE, current_color: Color = Color.WHITE, next_color: Color = Color.WHITE) -> void:
	_prev_label.text = prev_text
	_prev_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if prev_small else NORMAL_FONT_SIZE)
	_prev_label.add_theme_color_override("font_color", prev_color)
	_current_label.text = current_text
	_current_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if current_small else NORMAL_FONT_SIZE)
	_current_label.add_theme_color_override("font_color", current_color)
	_next_label.text = next_text
	_next_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if next_small else NORMAL_FONT_SIZE)
	_next_label.add_theme_color_override("font_color", next_color)

## --- Headless test hooks ---

func cell_text_for_test(position: StringName) -> String:
	match position:
		&"prev": return _prev_label.text
		&"current": return _current_label.text
		&"next": return _next_label.text
		_: return ""

func cell_font_size_for_test(position: StringName) -> int:
	match position:
		&"prev": return _prev_label.get_theme_font_size("font_size")
		&"current": return _current_label.get_theme_font_size("font_size")
		&"next": return _next_label.get_theme_font_size("font_size")
		_: return 0

func cell_color_for_test(position: StringName) -> Color:
	match position:
		&"prev": return _prev_label.get_theme_color("font_color")
		&"current": return _current_label.get_theme_color("font_color")
		&"next": return _next_label.get_theme_color("font_color")
		_: return Color.WHITE
