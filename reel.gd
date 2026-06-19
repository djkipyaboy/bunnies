class_name Reel
extends Node2D

## A single slot-machine reel that scrolls through bunny-themed symbols.
## Owned by a parent SlotMachine scene; communicates results exclusively via signals.

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted the moment the reel begins accelerating.
signal spin_started

## Emitted once the reel has fully stopped. [param result] contains the string IDs
## of every currently visible symbol, top-to-bottom.
signal spin_stopped(result: Array[String])

## Emitted each time a new symbol scrolls into the topmost visible slot.
signal symbol_landed(symbol_id: String)

# ---------------------------------------------------------------------------
# State machine
# ---------------------------------------------------------------------------

enum State {
	IDLE,
	SPINNING,
	STOPPING,
}

# ---------------------------------------------------------------------------
# Exported configuration
# ---------------------------------------------------------------------------

## Ordered list of symbol IDs that make up the full reel strip (e.g. "bunny_lop", "bunny_rex").
@export var symbol_ids: Array[String] = []

## Total number of symbol slots on the virtual reel strip before it wraps.
@export var reel_strip_length: int = 20

## Scroll speed in pixels per second while the reel is in SPINNING state.
@export var spin_speed: float = 600.0

## How many symbols are visible in the viewport window at once.
@export var visible_symbol_count: int = 3

## Height in pixels of a single symbol cell; drives scroll-to-symbol mapping.
@export var symbol_height: float = 128.0

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _state: State = State.IDLE

## Current vertical scroll offset within the reel strip (pixels, wraps on overflow).
var _scroll_position: float = 0.0

## Target scroll position set during STOPPING so the reel snaps to a valid symbol boundary.
var _target_scroll_position: float = 0.0

## Deceleration rate applied once stop() is called, in pixels/second².
var _deceleration: float = 1800.0

## Current effective speed; transitions from spin_speed toward 0.0 during STOPPING.
var _current_speed: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Defer symbol node construction until the tree is fully built.
	_build_symbol_nodes()

func _physics_process(delta: float) -> void:
	match _state:
		State.IDLE:
			pass

		State.SPINNING:
			_scroll_position += _current_speed * delta
			_wrap_scroll_position()
			_update_symbol_positions()

		State.STOPPING:
			# Decelerate toward the snapped target; finalize when close enough.
			_current_speed = maxf(_current_speed - _deceleration * delta, 0.0)
			_scroll_position += _current_speed * delta
			_wrap_scroll_position()
			_update_symbol_positions()

			if _current_speed == 0.0:
				_finalize_stop()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Begin spinning the reel. No-op if already in motion.
func spin() -> void:
	if _state != State.IDLE:
		return

	_state = State.SPINNING
	_current_speed = spin_speed
	spin_started.emit()
	# TODO: trigger any wind-up animation or sound cue here.

## Request the reel to decelerate and stop on the next valid symbol boundary.
## The actual stop is confirmed by spin_stopped being emitted, not this call.
func stop() -> void:
	if _state != State.SPINNING:
		return

	_state = State.STOPPING
	_target_scroll_position = _calculate_stop_target()
	# TODO: begin deceleration curve toward _target_scroll_position.

## Returns the string IDs of the [member visible_symbol_count] currently visible symbols,
## ordered top-to-bottom. Safe to call from any state.
func get_visible_symbols() -> Array[String]:
	var result: Array[String] = []
	# TODO: derive symbol indices from _scroll_position and populate result.
	return result

## Replaces the reel's symbol strip at runtime (e.g. for progressive unlock).
## Rebuilds internal display nodes to match the new strip.
func set_symbols(symbols: Array[String]) -> void:
	symbol_ids = symbols
	_build_symbol_nodes()
	# TODO: validate that symbols is non-empty and reel_strip_length is respected.

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Instantiates or recycles Sprite2D/TextureRect nodes for each visible slot.
func _build_symbol_nodes() -> void:
	# TODO: remove existing child symbol nodes, then create visible_symbol_count
	#       new nodes positioned symbol_height apart along the local Y axis.
	pass

## Adjusts child node positions to reflect the current _scroll_position.
func _update_symbol_positions() -> void:
	# TODO: map _scroll_position to symbol indices, assign textures, set positions.
	pass

## Keeps _scroll_position within [0, reel_strip_length * symbol_height) to avoid float drift.
func _wrap_scroll_position() -> void:
	var strip_pixel_length: float = float(reel_strip_length) * symbol_height
	if strip_pixel_length > 0.0:
		_scroll_position = fmod(_scroll_position, strip_pixel_length)

## Snaps _target_scroll_position to the nearest symbol boundary so the reel
## always halts on a whole symbol rather than mid-cell.
func _calculate_stop_target() -> float:
	# TODO: choose a random or predetermined stop index, return its pixel offset.
	return roundf(_scroll_position / symbol_height) * symbol_height

## Called once speed reaches zero; emits spin_stopped with the final visible symbols.
func _finalize_stop() -> void:
	_state = State.IDLE
	_scroll_position = _target_scroll_position
	_wrap_scroll_position()
	_update_symbol_positions()

	var final_symbols: Array[String] = get_visible_symbols()

	# Emit symbol_landed for each visible symbol so listeners can react individually.
	for symbol_id: String in final_symbols:
		symbol_landed.emit(symbol_id)

	spin_stopped.emit(final_symbols)
