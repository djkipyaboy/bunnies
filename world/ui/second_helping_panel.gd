class_name SecondHelpingPanel
extends Panel

## The view for Cooking's opt-in "Second Helping" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2). Mirrors ForagingPanel's shake/bank shape (minus the presentation
## spin-animation polish ForagingPanel later added -- out of scope for this pass), capped at exactly
## 1 reroll.

signal second_helping_resolved(bonus_quantity: int)

const PANEL_W: float = 320.0
const PANEL_H: float = 160.0
const STRIP_GAP: float = 100.0

var _minigame: SecondHelpingMinigame
var _reel_strips: Array[ReelStripWidget] = []
var _reroll_button: Button
var _bank_button: Button
var _result_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

func open_for(reel_count: int) -> void:
	_minigame = SecondHelpingMinigame.new(reel_count)
	_rebuild()
	visible = true

func is_open() -> bool:
	return visible

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()

	var faces: Array[ReelFace] = _minigame.current_faces()
	for i in range(faces.size()):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * STRIP_GAP, 16.0)
		add_child(strip)
		strip.set_cells("", _label_for_face(faces[i]), "", false, false, false, Color.WHITE, Color.WHITE, Color.WHITE)
		_reel_strips.append(strip)

	_result_label = Label.new()
	_result_label.text = "Bonus: +%d" % _minigame.bank()
	_result_label.position = Vector2(20.0, 70.0)
	add_child(_result_label)

	_reroll_button = Button.new()
	_reroll_button.text = "Reroll (%d left)" % _minigame.rerolls_remaining
	_reroll_button.disabled = _minigame.rerolls_remaining <= 0
	_reroll_button.position = Vector2(20.0, 100.0)
	_reroll_button.custom_minimum_size = Vector2(140.0, 32.0)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	add_child(_reroll_button)

	_bank_button = Button.new()
	_bank_button.text = "Bank"
	_bank_button.position = Vector2(170.0, 100.0)
	_bank_button.custom_minimum_size = Vector2(100.0, 32.0)
	_bank_button.pressed.connect(_on_bank_pressed)
	add_child(_bank_button)

static func _label_for_face(face: ReelFace) -> String:
	return "Bonus +%d" % face.bonus_magnitude if face.bonus_mode == &"bonus_quantity" else "Baseline"

func _on_reroll_pressed() -> void:
	_minigame.reroll()
	_rebuild()

func _on_bank_pressed() -> void:
	var bonus: int = _minigame.bank()
	visible = false
	second_helping_resolved.emit(bonus)

## --- Headless test hooks ---

func reel_count_for_test() -> int:
	return _reel_strips.size()

func rerolls_remaining_for_test() -> int:
	return _minigame.rerolls_remaining

func press_reroll_for_test() -> void:
	_reroll_button.pressed.emit()

func press_bank_for_test() -> void:
	_bank_button.pressed.emit()
