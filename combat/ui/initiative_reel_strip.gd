class_name InitiativeReelStrip
extends Control

## Visual scrolling view of one InitiativeReel — a small single-digit "odometer" spinner next to
## a combatant's panel (2026-08-16 visible-initiative-reels spec §2). It does NOT decide the
## result: TurnManager.roll_initiative() already determined every combatant's digits before this
## ever spins; this widget is just told which face index to land on and animates to it, mirroring
## ReelStrip's existing spin-then-settle contract but sized for a single digit rather than a
## payline grid, and with plain digit-labeled cells instead of ReelStrip's tier-colored ones
## (an InitiativeReel's faces carry no meaningful result_tier).

signal strip_settled

const CELL_HEIGHT: float = 32.0
const VISIBLE_CELLS: int = 1       # a single-digit window — no payline grid to show
const REPEATS: int = 4             # how many times the 10-face digit list is stacked into the strip
const SPIN_DURATION: float = 0.9   # slightly faster than ReelStrip's 1.15s — these are the small reels

var _reel: InitiativeReel
var _face_count: int = 0
var _strip: Control          # the moving column of cells
var _viewport: Control       # clipped window

func _ready() -> void:
	custom_minimum_size = Vector2(40, CELL_HEIGHT * VISIBLE_CELLS)
	size = custom_minimum_size

## Builds the cell column for [param reel] and resets it to the top.
func configure(reel: InitiativeReel) -> void:
	_reel = reel
	_face_count = reel.faces.size()

	if _viewport != null:
		_viewport.queue_free()

	_viewport = Control.new()
	_viewport.clip_contents = true
	_viewport.size = Vector2(40, CELL_HEIGHT * VISIBLE_CELLS)
	add_child(_viewport)

	_strip = Control.new()
	_viewport.add_child(_strip)

	var total_cells: int = _face_count * REPEATS
	for j: int in range(total_cells):
		var face: ReelFace = reel.faces[j % _face_count]
		_strip.add_child(_make_cell(face, j))

	_strip.position = Vector2.ZERO

func _make_cell(face: ReelFace, index: int) -> Control:
	var cell := ColorRect.new()
	cell.position = Vector2(0, float(index) * CELL_HEIGHT)
	cell.size = Vector2(40, CELL_HEIGHT - 2.0)
	cell.color = Color(0.25, 0.25, 0.3)
	var label := Label.new()
	label.text = str(face.digit)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = cell.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	return cell

## Scrolls and snaps so that face [param target_index] lands centered, after [param delay] seconds.
## Emits [signal strip_settled] when motion stops. Mirrors ReelStrip.play_to()'s exact tween shape.
func play_to(target_index: int, delay: float = 0.0) -> void:
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
