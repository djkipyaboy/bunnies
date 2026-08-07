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
const ARROW_W: float = 12.0

var _prev_label: Label
var _current_label: Label
var _next_label: Label
var _left_arrow: Label
var _right_arrow: Label

func _ready() -> void:
	custom_minimum_size = Vector2(CELL_W, CELL_H * 3.0)
	size = custom_minimum_size

	_prev_label = _make_cell_label(0.0)
	add_child(_prev_label)

	_current_label = _make_cell_label(CELL_H)
	add_child(_current_label)

	_next_label = _make_cell_label(CELL_H * 2.0)
	add_child(_next_label)

	# Task 4 (2026-08-07 professions-playtest-fixes), fix round 1: arrows sit INSIDE the strip's own
	# CELL_W column, near its left/right edges, rather than protruding outside it. The original
	# outside-the-column placement overlapped the NEXT column's arrow in every real multi-reel caller
	# (Fishing/Tempering Reels/Second Helping all space columns exactly 100px apart with CELL_W=90 --
	# only a 10px gap, and each arrow protruded 18px). Placing them inside guarantees zero cross-column
	# overlap regardless of caller spacing, since nothing rendered by this widget now extends past its
	# own [0, CELL_W] bounds. Short cell text (single words like "Fail"/"Bumper"/"Baseline") centered in
	# CELL_W leaves comfortable margin at both edges for a 12px-wide arrow.
	_left_arrow = Label.new()
	_left_arrow.text = "▶"
	_left_arrow.position = Vector2(2.0, CELL_H)
	_left_arrow.custom_minimum_size = Vector2(ARROW_W, CELL_H)
	_left_arrow.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_left_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_left_arrow)

	_right_arrow = Label.new()
	_right_arrow.text = "◀"
	_right_arrow.position = Vector2(CELL_W - ARROW_W - 2.0, CELL_H)
	_right_arrow.custom_minimum_size = Vector2(ARROW_W, CELL_H)
	_right_arrow.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	_right_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_right_arrow)

func _make_cell_label(y: float) -> Label:
	var label := Label.new()
	label.position = Vector2(0.0, y)
	label.custom_minimum_size = Vector2(CELL_W, CELL_H)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Structural backstop against a long caller-supplied label overflowing into the next reel column
	# (final-review finding, 2026-08-02 salvaging-and-cooking professions review -- Tempering Reels was
	# the first multi-column caller with long face text; Fishing/Foraging's own labels already fit, so
	# this is a no-op for them). Callers should still keep labels short -- see
	# TemperingReelsPanel._label_for_face() for the actual fix that made its labels fit CELL_W.
	label.clip_text = true
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

## Confirms the clip_text structural backstop (final-review finding, 2026-08-02) is actually set,
## regardless of which caller/label text is in play.
func cell_clips_text_for_test(position: StringName) -> bool:
	match position:
		&"prev": return _prev_label.clip_text
		&"current": return _current_label.clip_text
		&"next": return _next_label.clip_text
		_: return false

func cell_color_for_test(position: StringName) -> Color:
	match position:
		&"prev": return _prev_label.get_theme_color("font_color")
		&"current": return _current_label.get_theme_color("font_color")
		&"next": return _next_label.get_theme_color("font_color")
		_: return Color.WHITE

func left_arrow_text_for_test() -> String:
	return _left_arrow.text

func right_arrow_text_for_test() -> String:
	return _right_arrow.text

func left_arrow_x_for_test() -> float:
	return _left_arrow.position.x

func right_arrow_x_for_test() -> float:
	return _right_arrow.position.x

## Confirms both arrows sit near the strip's own left/right edges (not the center, not outside the
## [0, CELL_W] column) and at the current cell's vertical band (CELL_H) -- proving they flank the
## center cell from within the column, per Task 4 fix round 1's redesign.
func arrows_flank_center_cell_for_test() -> bool:
	var left_near_left_edge: bool = _left_arrow.position.x < CELL_W / 2.0
	var right_near_right_edge: bool = _right_arrow.position.x + _right_arrow.custom_minimum_size.x > CELL_W / 2.0
	var both_inside_column: bool = _left_arrow.position.x >= 0.0 and (_right_arrow.position.x + _right_arrow.custom_minimum_size.x) <= CELL_W
	var left_aligned: bool = is_equal_approx(_left_arrow.position.y, CELL_H)
	var right_aligned: bool = is_equal_approx(_right_arrow.position.y, CELL_H)
	return left_near_left_edge and right_near_right_edge and both_inside_column and left_aligned and right_aligned
