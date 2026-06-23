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

## Toggles the WILD highlight on this strip (Sticky-Wild Ultimate target). Cosmetic only.
func set_wild(on: bool) -> void:
	modulate = Color(1.6, 1.4, 0.4) if on else Color(1, 1, 1)

## Toggles a visible "RE-ROLL" tag on this strip (Chancer post-spin Re-roll / Wildcard Gamble target).
## Legibility pillar: the player must always see which reel was re-rolled. Cosmetic only; the result is
## owned by [CombatResolver]. Placeholder styling — judged in play-test. A persistent child (not a tween)
## so it stays visible while the spin is reviewed; toggling off removes it.
func set_rerolled(on: bool) -> void:
	var existing: Node = get_node_or_null("RerollTag")
	if on:
		if existing != null:
			return
		var tag := Label.new()
		tag.name = "RerollTag"
		tag.text = "RE-ROLL"
		tag.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		tag.add_theme_font_size_override("font_size", 14)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.size = Vector2(110, 18)
		tag.position = Vector2(0, -20)  # sits just above the strip window
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tag)
	elif existing != null:
		existing.queue_free()

## Briefly highlights one of the 3 visible window cells (row 0=top,1=center,2=bottom) as part of a
## winning payline. Cosmetic only. Exact styling is placeholder — judged in play-test.
func flash_cell(row: int) -> void:
	var marker := ColorRect.new()
	marker.color = Color(1.0, 0.95, 0.4, 0.35)
	marker.size = Vector2(110, CELL_HEIGHT)
	marker.position = Vector2(0, CELL_HEIGHT * float(row))
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(marker.queue_free)
