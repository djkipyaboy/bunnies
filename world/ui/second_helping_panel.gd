class_name SecondHelpingPanel
extends Panel

## The view for Cooking's opt-in "Second Helping" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2; presentation spin animation added 2026-08-07
## professions-playtest-fixes plan Task 9, mirroring ForagingPanel's identical pattern). The
## underlying SecondHelpingMinigame model is untouched -- its pick is still instant and random;
## only how long the reveal takes to show changed. Capped at exactly 1 reroll.

signal second_helping_resolved(bonus_quantity: int)

const PANEL_W: float = 320.0
const PANEL_H: float = 160.0
const STRIP_GAP: float = 100.0
## [ASSUMPTION] spin duration/tick rate, matching ForagingPanel's own placeholder numbers exactly
## (2026-08-07 professions-playtest-fixes plan Task 9) -- tuned at playtest like everything else.
const SPIN_DURATION_SECONDS: float = 0.6
const SPIN_TICK_SECONDS: float = 0.08
## Fixed display order the spin cycles through -- purely visual, carries no gameplay meaning, and
## always lands on whatever SecondHelpingMinigame already picked. Mirrors
## ForagingPanel.TIER_DISPLAY_ORDER's identical role.
const FACE_DISPLAY_ORDER: Array[String] = ["Baseline", "Bonus"]

var _minigame: SecondHelpingMinigame
var _reel_strips: Array[ReelStripWidget] = []
var _reroll_button: Button
var _bank_button: Button
var _result_label: Label

var _spinning: bool = false
var _spin_time_remaining: float = 0.0
var _spin_tick_remaining: float = 0.0
var _spin_visual_indices: Array[int] = []

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

func open_for(reel_count: int) -> void:
	_minigame = SecondHelpingMinigame.new(reel_count)
	_rebuild()
	visible = true
	_start_spin()

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible or not _spinning:
		return
	_advance_spin(delta)

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()

	var faces: Array[ReelFace] = _minigame.current_faces()
	_spin_visual_indices.resize(faces.size())
	for i in range(faces.size()):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * STRIP_GAP, 16.0)
		add_child(strip)
		_reel_strips.append(strip)

	_result_label = Label.new()
	_result_label.position = Vector2(20.0, 70.0)
	add_child(_result_label)

	_reroll_button = Button.new()
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

func _start_spin() -> void:
	_spinning = true
	_spin_time_remaining = SPIN_DURATION_SECONDS
	_spin_tick_remaining = SPIN_TICK_SECONDS
	_reroll_button.disabled = true
	_bank_button.disabled = true
	_result_label.text = ""
	_reroll_button.text = "Reroll (%d left)" % _minigame.rerolls_remaining
	for i in range(_spin_visual_indices.size()):
		_spin_visual_indices[i] = 0
	_refresh_spin_visual()

func _advance_spin(delta: float) -> void:
	_spin_time_remaining -= delta
	_spin_tick_remaining -= delta
	if _spin_time_remaining <= 0.0:
		_land_spin()
		return
	if _spin_tick_remaining <= 0.0:
		_spin_tick_remaining += SPIN_TICK_SECONDS
		for i in range(_spin_visual_indices.size()):
			_spin_visual_indices[i] = (_spin_visual_indices[i] + 1) % FACE_DISPLAY_ORDER.size()
		_refresh_spin_visual()

func _land_spin() -> void:
	_spinning = false
	var faces: Array[ReelFace] = _minigame.current_faces()
	for i in range(faces.size()):
		var landed_text: String = _label_for_face(faces[i])
		var landed_index: int = FACE_DISPLAY_ORDER.find("Bonus" if faces[i].bonus_mode == &"bonus_quantity" else "Baseline")
		_spin_visual_indices[i] = landed_index if landed_index >= 0 else 0
	_reroll_button.disabled = _minigame.rerolls_remaining <= 0
	_bank_button.disabled = false
	# SecondHelpingMinigame.bank() is a pure read of _current_faces (see world/second_helping_minigame.gd)
	# -- calling it here for display is safe and side-effect-free, exactly like the original
	# (pre-spin-animation) _rebuild() already did; the REAL bank happens only in _on_bank_pressed().
	_result_label.text = "Bonus: +%d" % _minigame.bank()
	_refresh_spin_visual()

func _refresh_spin_visual() -> void:
	var faces: Array[ReelFace] = _minigame.current_faces()
	var order_size: int = FACE_DISPLAY_ORDER.size()
	for i in range(_reel_strips.size()):
		var idx: int = _spin_visual_indices[i]
		var prev_index: int = (idx - 1 + order_size) % order_size
		var next_index: int = (idx + 1) % order_size
		_reel_strips[i].set_cells(FACE_DISPLAY_ORDER[prev_index], FACE_DISPLAY_ORDER[idx], FACE_DISPLAY_ORDER[next_index])

func _on_reroll_pressed() -> void:
	if _spinning:
		return
	_minigame.reroll()
	_start_spin()

func _on_bank_pressed() -> void:
	if _spinning:
		return
	var bonus: int = _minigame.bank()
	visible = false
	second_helping_resolved.emit(bonus)

## --- Headless test hooks ---

func reel_count_for_test() -> int:
	return _reel_strips.size()

func rerolls_remaining_for_test() -> int:
	return _minigame.rerolls_remaining

func press_reroll_for_test() -> void:
	if _spinning:
		return
	_on_reroll_pressed()

func press_bank_for_test() -> void:
	if _spinning:
		return
	_on_bank_pressed()

func is_spinning_for_test() -> bool:
	return _spinning

## Advances the presentation-only spin by [param delta] seconds -- a no-op if not currently
## spinning. Mirrors ForagingPanel.advance_spin_for_test()'s identical convention.
func advance_spin_for_test(delta: float) -> void:
	if _spinning:
		_advance_spin(delta)
