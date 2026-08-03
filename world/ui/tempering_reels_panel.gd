class_name TemperingReelsPanel
extends Panel

## The view for Salvaging's opt-in "Tempering Reels" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.1). Mirrors FishingPanel's reel-stop-phase structure exactly (one
## ReelStripWidget + one Stop button per reel column, driven by TemperingReelsMinigame's
## advance()/stop()/current_face()/all_stopped()) -- but opens STRAIGHT into that phase; there's no
## targeting/hook step here, since crafting doesn't need a shadow to hunt.

signal tempering_resolved(bonus_stats: Stats)

const PANEL_W: float = 420.0
const PANEL_H: float = 220.0
const STRIP_GAP: float = 100.0

var _minigame: TemperingReelsMinigame
var _reel_strips: Array[ReelStripWidget] = []
var _stop_buttons: Array[Button] = []
var _confirm_button: Button
var _result_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

func open_for(primary_stat: StringName, secondary_stat: StringName, tertiary_stat: StringName, stat_count: int) -> void:
	_minigame = TemperingReelsMinigame.new(primary_stat, secondary_stat, tertiary_stat, stat_count)
	_build_reel_stop()
	visible = true

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible:
		return
	_minigame.advance(delta)
	_refresh_reel_strips()

func _build_reel_stop() -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()
	_stop_buttons.clear()

	var reel_count: int = _minigame.reels.size()
	for i in range(reel_count):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * STRIP_GAP, 20.0)
		add_child(strip)
		_reel_strips.append(strip)

		var btn := Button.new()
		btn.text = "Stop"
		btn.position = Vector2(20.0 + i * STRIP_GAP, 130.0)
		btn.custom_minimum_size = Vector2(90.0, 36.0)
		var col: int = i
		btn.pressed.connect(func() -> void: _on_stop_pressed(col))
		add_child(btn)
		_stop_buttons.append(btn)

	_confirm_button = Button.new()
	_confirm_button.text = "Confirm"
	_confirm_button.disabled = true
	_confirm_button.position = Vector2(20.0, 170.0)
	_confirm_button.custom_minimum_size = Vector2(120.0, 36.0)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_button)

	_refresh_reel_strips()

func _refresh_reel_strips() -> void:
	for i in range(_reel_strips.size()):
		var prev: ReelFace = _minigame.face_at(i, -1)
		var current: ReelFace = _minigame.face_at(i, 0)
		var next: ReelFace = _minigame.face_at(i, 1)
		_reel_strips[i].set_cells(
			_label_for_face(prev), _label_for_face(current), _label_for_face(next),
			false, false, false,
			Color.WHITE, Color.WHITE, Color.WHITE)

static func _label_for_face(face: ReelFace) -> String:
	match face.bonus_mode:
		&"stat_value":
			return "+%d" % face.bonus_magnitude
		&"amplify_primary":
			return "Amplify (+%d)" % face.bonus_magnitude
		&"amplify_secondary":
			return "Amplify 2nd (+%d)" % face.bonus_magnitude
		&"bonus_tertiary":
			return "Bonus (+%d)" % face.bonus_magnitude
		_:
			return ""

func _on_stop_pressed(col: int) -> void:
	_minigame.stop(col)
	_stop_buttons[col].disabled = true
	_refresh_reel_strips()
	if _minigame.all_stopped():
		_confirm_button.disabled = false

func _on_confirm_pressed() -> void:
	var bonus_stats: Stats = _minigame.resolve()
	visible = false
	tempering_resolved.emit(bonus_stats)

## --- Headless test hooks ---

func reel_count_for_test() -> int:
	return _reel_strips.size()

func all_stopped_for_test() -> bool:
	return _minigame.all_stopped()

func advance_for_test(delta: float) -> void:
	if visible:
		_minigame.advance(delta)
		_refresh_reel_strips()

func press_stop_for_test(col: int) -> void:
	_stop_buttons[col].pressed.emit()

func press_confirm_for_test() -> void:
	_confirm_button.pressed.emit()
