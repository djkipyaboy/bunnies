class_name FishingPanel
extends Panel

## Fishing mini-game overlay -- claw-machine targeting + manual-stop multi-reel catch (2026-08-01
## gathering-profession-minigames spec section 3). Mirrors RandomEncounterPanel's "clear and
## rebuild children per phase" convention (_build_targeting/_build_reel_stop/_build_result) rather
## than toggling visibility on a fixed set of pre-built children, since the phases have genuinely
## different content (a movable hook + shadows vs. a row of reel displays vs. a result message).

signal fishing_completed(item_name: String, quantity: int)
## Fires unconditionally when the panel closes, catch or miss, carrying the full combined
## event-log line for this attempt (2026-08-02 gathering-playtest-fixes spec section 4) -- the ONE
## signal callers should use both to write the Fishing event-log entry and to resume PC movement
## (fishing_completed is informational-only and does not fire on a miss).
signal fishing_closed(log_line: String)

const PANEL_W: float = 520.0
const PANEL_H: float = 440.0
const WATER_RECT: Rect2 = Rect2(20.0, 20.0, 480.0, 240.0)
## [ASSUMPTION] hook hit-radius/speed, tuned at playtest.
const HOOK_RADIUS: float = 10.0
const HOOK_SPEED: float = 140.0
## [ASSUMPTION] shadow count range per targeting-phase layout, tuned at playtest.
const MIN_SHADOWS: int = 3
const MAX_SHADOWS: int = 6
## [ASSUMPTION] reel composition (spec section 3's own example numbers): 4 Fail, 4 Success,
## 2 Critical out of 10 faces, tuned at playtest.
const REEL_COMPOSITION: Array = [[&"fail", 4], [&"success", 4], [&"critical", 2]]
## [ASSUMPTION] tier -> color mapping (2026-08-02 gathering-reel-colors-and-sizing spec section 3),
## placeholder until real reel-face icons exist. Red/Success/Critical per the player's own choice.
const FAIL_COLOR: Color = Color(0.85, 0.2, 0.2)
const SUCCESS_COLOR: Color = Color(0.2, 0.8, 0.2)
const CRITICAL_COLOR: Color = Color(0.3, 0.5, 0.95)

var _party_inventory: PartyInventory
var _bucket_configs: Dictionary = {}
var _shadows: Array[Dictionary] = []
var _hook_position: Vector2 = Vector2.ZERO
var _phase: StringName = &"targeting"   # "targeting" | "reel_stop" | "result"
var _minigame: FishingMinigame
var _active_bucket: StringName = &""

var _hook_control: ColorRect
var _hook_button: Button
var _miss_label: Label
var _reel_strips: Array[ReelStripWidget] = []
var _stop_buttons: Array[Button] = []
var _result_label: Label
var _continue_button: Button
var _pending_item_name: String = ""
var _pending_quantity: int = 0
var _pending_log_line: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false
	scale = Vector2(2.0, 2.0)

## Opens a fresh round. [param forced_shadows] empty (every real call site's default) means
## "generate a real random layout"; tests pass a deterministic layout instead.
func open_for(bucket_configs: Dictionary, party_inventory: PartyInventory, forced_shadows: Array[Dictionary] = []) -> void:
	_party_inventory = party_inventory
	_bucket_configs = bucket_configs
	_pending_item_name = ""
	_pending_quantity = 0
	_pending_log_line = ""
	_shadows = forced_shadows.duplicate(true) if not forced_shadows.is_empty() else FishingShadowGenerator.generate(WATER_RECT, MIN_SHADOWS, MAX_SHADOWS)
	_hook_position = Vector2(WATER_RECT.position.x + WATER_RECT.size.x / 2.0, WATER_RECT.position.y + WATER_RECT.size.y / 2.0)
	_phase = &"targeting"
	_build_targeting()
	visible = true

func is_open() -> bool:
	return visible

func current_phase_for_test() -> StringName:
	return _phase

func shadows_for_test() -> Array[Dictionary]:
	return _shadows

func miss_label_visible_for_test() -> bool:
	return _miss_label.visible

func _process(delta: float) -> void:
	if not visible:
		return
	if _phase == &"targeting":
		_update_hook_position(delta)
	elif _phase == &"reel_stop":
		_minigame.advance(delta)
		_refresh_reel_strips()

func _update_hook_position(delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up"))
	var velocity: Vector2 = PCController.movement_velocity(input_vector, HOOK_SPEED, false)
	_hook_position += velocity * delta
	_hook_position.x = clampf(_hook_position.x, WATER_RECT.position.x, WATER_RECT.position.x + WATER_RECT.size.x)
	_hook_position.y = clampf(_hook_position.y, WATER_RECT.position.y, WATER_RECT.position.y + WATER_RECT.size.y)
	if _hook_control != null:
		_hook_control.position = _hook_position - Vector2(HOOK_RADIUS, HOOK_RADIUS)

func _build_targeting() -> void:
	for child in get_children():
		child.queue_free()

	var water_bg := ColorRect.new()
	water_bg.color = Color(0.15, 0.35, 0.55)
	water_bg.position = WATER_RECT.position
	water_bg.size = WATER_RECT.size
	add_child(water_bg)

	for shadow: Dictionary in _shadows:
		var radius: float = shadow["radius"]
		var r := ColorRect.new()
		r.color = Color(0.05, 0.1, 0.2, 0.8)
		r.position = shadow["position"] - Vector2(radius, radius)
		r.size = Vector2(radius * 2.0, radius * 2.0)
		add_child(r)

	_hook_control = ColorRect.new()
	_hook_control.color = Color(0.9, 0.9, 0.2)
	_hook_control.size = Vector2(HOOK_RADIUS * 2.0, HOOK_RADIUS * 2.0)
	_hook_control.position = _hook_position - Vector2(HOOK_RADIUS, HOOK_RADIUS)
	add_child(_hook_control)

	_hook_button = Button.new()
	_hook_button.text = "Drop Hook"
	_hook_button.position = Vector2(WATER_RECT.position.x, WATER_RECT.position.y + WATER_RECT.size.y + 16.0)
	_hook_button.custom_minimum_size = Vector2(150.0, 40.0)
	_hook_button.pressed.connect(_on_hook_pressed)
	add_child(_hook_button)

	_miss_label = Label.new()
	_miss_label.text = "The hook came up empty — try again!"
	_miss_label.position = Vector2(WATER_RECT.position.x, WATER_RECT.position.y + WATER_RECT.size.y + 64.0)
	_miss_label.custom_minimum_size = Vector2(WATER_RECT.size.x, 30.0)
	_miss_label.visible = false
	add_child(_miss_label)

func move_hook_to_for_test(pos: Vector2) -> void:
	_hook_position = pos
	if _hook_control != null:
		_hook_control.position = _hook_position - Vector2(HOOK_RADIUS, HOOK_RADIUS)

func press_hook_button_for_test() -> void:
	_hook_button.pressed.emit()

func _on_hook_pressed() -> void:
	if _phase != &"targeting":
		return
	var hooked_index: int = -1
	for i in range(_shadows.size()):
		var shadow: Dictionary = _shadows[i]
		if _hook_position.distance_to(shadow["position"]) <= float(shadow["radius"]) + HOOK_RADIUS:
			hooked_index = i
			break
	if hooked_index == -1:
		_miss_label.visible = true
		return
	var bucket: StringName = _shadows[hooked_index]["size_bucket"]
	var reel_count: int = FishingShadowGenerator.reel_count_for_bucket(bucket)
	var reels: Array[FishingReel] = []
	for i in range(reel_count):
		reels.append(FishingReel.make_default(REEL_COMPOSITION))
	_begin_reel_stop(bucket, reels)

## Test-only bypass straight into the reel-stop phase with caller-supplied deterministic reels,
## skipping the random targeting phase entirely -- lets tests prove the resolve/grant path exactly,
## since the real _on_hook_pressed() path always builds shuffled reels internally.
func begin_reel_stop_for_test(bucket: StringName, forced_reels: Array[FishingReel]) -> void:
	_begin_reel_stop(bucket, forced_reels)

func _begin_reel_stop(bucket: StringName, reels: Array[FishingReel]) -> void:
	_active_bucket = bucket
	_minigame = FishingMinigame.new(reels)
	_phase = &"reel_stop"
	_build_reel_stop(reels.size())

func _build_reel_stop(reel_count: int) -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()
	_stop_buttons.clear()
	# queue_free() is deferred, not synchronous -- without this, a stale _miss_label reference
	# left visible=true from a prior miss would still read as visible here even though the whole
	# targeting phase (which owns it) has just been torn down.
	if _miss_label != null:
		_miss_label.visible = false

	for i in range(reel_count):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * 100.0, 20.0)
		add_child(strip)
		_reel_strips.append(strip)

		var btn := Button.new()
		btn.text = "Stop"
		btn.position = Vector2(20.0 + i * 100.0, 130.0)
		btn.custom_minimum_size = Vector2(90.0, 36.0)
		var col: int = i
		btn.pressed.connect(func() -> void: _on_stop_pressed(col))
		add_child(btn)
		_stop_buttons.append(btn)

	_refresh_reel_strips()

func _refresh_reel_strips() -> void:
	for i in range(_reel_strips.size()):
		var prev: ReelFace = _minigame.face_at(i, -1)
		var current: ReelFace = _minigame.face_at(i, 0)
		var next: ReelFace = _minigame.face_at(i, 1)
		_reel_strips[i].set_cells(
			String(prev.fishing_tier).capitalize(), String(current.fishing_tier).capitalize(), String(next.fishing_tier).capitalize(),
			prev.fishing_tier == &"critical", current.fishing_tier == &"critical", next.fishing_tier == &"critical",
			_color_for_fishing_tier(prev.fishing_tier), _color_for_fishing_tier(current.fishing_tier), _color_for_fishing_tier(next.fishing_tier))

static func _color_for_fishing_tier(tier: StringName) -> Color:
	match tier:
		&"fail": return FAIL_COLOR
		&"success": return SUCCESS_COLOR
		&"critical": return CRITICAL_COLOR
		_: return Color.WHITE

func advance_for_test(delta: float) -> void:
	if _phase == &"reel_stop":
		_minigame.advance(delta)
		_refresh_reel_strips()

func press_stop_for_test(col: int) -> void:
	_stop_buttons[col].pressed.emit()

## Exposes one reel column's ReelStripWidget directly so tests can read back its cells/font sizes
## via the widget's own test hooks (2026-08-02 gathering-playtest-fixes spec).
func reel_strip_for_test(col: int) -> ReelStripWidget:
	return _reel_strips[col]

func _on_stop_pressed(col: int) -> void:
	_minigame.stop(col)
	_stop_buttons[col].disabled = true
	_refresh_reel_strips()
	if _minigame.all_stopped():
		_resolve()

func _resolve() -> void:
	var outcome: Dictionary = _minigame.resolve()
	_phase = &"result"

	var tier_names: Array[String] = []
	for i in range(_minigame.reels.size()):
		tier_names.append(String(_minigame.current_face(i).fishing_tier).capitalize())
	var verdict: String = "Failed"
	if outcome["caught"]:
		verdict = "Critical Success" if int(outcome["quality_tier"]) > 0 else "Success"
	var log_line: String = "Fishing: [%s] — %s" % [", ".join(tier_names), verdict]

	if outcome["caught"]:
		var config: Dictionary = _bucket_configs.get(_active_bucket, {})
		var m := CraftingMaterial.new()
		m.material_type = config.get("material_type", &"")
		m.display_name = config.get("material_display_name", "")
		m.quantity = int(config.get("quantity", 1)) * int(outcome["quantity_multiplier"])
		m.quality_tier = int(outcome["quality_tier"])
		_party_inventory.give_material(m)
		_pending_item_name = m.display_name
		_pending_quantity = m.quantity
		var bonus_note: String = " (bonus quality)" if m.quality_tier > 0 else ""
		log_line += "! Caught: %s x%d%s" % [m.display_name, m.quantity, bonus_note]
		_build_result("You caught a %s! (x%d)" % [m.display_name, m.quantity])
	else:
		_pending_item_name = ""
		_pending_quantity = 0
		log_line += ". The fish got away."
		_build_result("The fish got away.")

	_pending_log_line = log_line

func _build_result(text: String) -> void:
	for child in get_children():
		child.queue_free()

	_result_label = Label.new()
	_result_label.text = text
	_result_label.position = Vector2(20.0, 20.0)
	_result_label.custom_minimum_size = Vector2(PANEL_W - 40.0, 60.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(20.0, 90.0)
	_continue_button.custom_minimum_size = Vector2(150.0, 40.0)
	_continue_button.pressed.connect(_on_continue_pressed)
	add_child(_continue_button)

func press_continue_for_test() -> void:
	_continue_button.pressed.emit()

func _on_continue_pressed() -> void:
	visible = false
	if _pending_item_name != "":
		fishing_completed.emit(_pending_item_name, _pending_quantity)
		_pending_item_name = ""   # also prevents a double-press from re-emitting
	fishing_closed.emit(_pending_log_line)
