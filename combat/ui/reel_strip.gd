class_name ReelStrip
extends Control

## Visual scrolling view of one [ActionReel] (the slot-machine juice). It does NOT decide the
## result — [CombatResolver] is the authority; the strip is told which face index to land on and
## animates to it. Emits [signal strip_settled] once it stops.

signal strip_settled

const CELL_HEIGHT: float = 64.0
const VISIBLE_CELLS: int = 3            # window shows 3 cells; the middle one is the result
const REPEATS: int = 7                  # how many times the face list is stacked into the strip
const SPIN_DURATION: float = 1.15       # tune for feel; raised from 0.65 (playtest: too fast)

# Placeholder per-tier visuals (colour + short label).
const TIER_STYLE := {
	ReelFace.ResultTier.CRIT_FAILURE: { "color": Color(0.45, 0.10, 0.12), "text": "CRIT-" },
	ReelFace.ResultTier.FAILURE:      { "color": Color(0.35, 0.35, 0.38), "text": "MISS" },
	ReelFace.ResultTier.NEUTRAL:      { "color": Color(0.62, 0.55, 0.20), "text": "UTIL" },
	ReelFace.ResultTier.SUCCESS:      { "color": Color(0.20, 0.50, 0.25), "text": "HIT" },
	ReelFace.ResultTier.CRIT_SUCCESS: { "color": Color(0.20, 0.65, 0.70), "text": "CRIT+" },
}

var _reel: ActionReel
var _face_count: int = 0
var _strip: Control          # the moving column of cells
var _viewport: Control       # clipped window

func _ready() -> void:
	custom_minimum_size = Vector2(110, CELL_HEIGHT * VISIBLE_CELLS)
	size = custom_minimum_size

## Builds the cell column for [param reel] and resets it to the top.
func configure(reel: ActionReel) -> void:
	_reel = reel
	_face_count = reel.faces.size()

	if _viewport != null:
		_viewport.queue_free()

	_viewport = Control.new()
	_viewport.clip_contents = true
	_viewport.size = Vector2(110, CELL_HEIGHT * VISIBLE_CELLS)
	add_child(_viewport)

	_strip = Control.new()
	_viewport.add_child(_strip)

	var total_cells: int = _face_count * REPEATS
	for j: int in range(total_cells):
		var face: ReelFace = reel.faces[j % _face_count]
		_strip.add_child(_make_cell(face, j))

	# Center window highlight frame (drawn on top, not part of the moving strip).
	var frame := Panel.new()
	frame.position = Vector2(0, CELL_HEIGHT * float(VISIBLE_CELLS - 1) * 0.5)
	frame.size = Vector2(110, CELL_HEIGHT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.modulate = Color(1, 1, 1, 0.0)  # invisible fill; we just want the border via theme default
	add_child(frame)

	_strip.position = Vector2.ZERO

func _make_cell(face: ReelFace, index: int) -> Control:
	var cell := ColorRect.new()
	cell.position = Vector2(0, float(index) * CELL_HEIGHT)
	cell.size = Vector2(110, CELL_HEIGHT - 4.0)
	var style: Dictionary = TIER_STYLE.get(face.result_tier, { "color": Color.DIM_GRAY, "text": "?" })
	cell.color = style["color"]
	var label := Label.new()
	label.text = str(style["text"])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = cell.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	return cell

## Scrolls and snaps so that face [param target_index] lands centered, after [param delay] seconds.
## Emits [signal strip_settled] when motion stops.
func play_to(target_index: int, delay: float = 0.0) -> void:
	# Land on a cell deep in the strip whose face matches target_index, so it scrolls a long way.
	var landing_repeat: int = REPEATS - 2
	var landing_cell: int = landing_repeat * _face_count + target_index
	var window_center_top: float = CELL_HEIGHT * float(VISIBLE_CELLS - 1) * 0.5
	var final_y: float = window_center_top - float(landing_cell) * CELL_HEIGHT

	_strip.position.y = 0.0
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(_strip, "position:y", final_y, SPIN_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func() -> void: strip_settled.emit())
