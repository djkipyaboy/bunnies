class_name SlotMachine
extends Node

signal spin_initiated
signal all_reels_stopped(results: Array)
signal payout_calculated(amount: int)
signal credits_changed(new_total: int)

enum State { READY, SPINNING, EVALUATING, PAYING_OUT }

@export var reel_count: int = 3
@export var bet_amount: int = 1
@export var credits: int = 100
@export var paytable: Dictionary = {}
@export var stop_stagger_delay: float = 0.3

var _state: State = State.READY
var _reels: Array[Reel] = []
var _stopped_reel_count: int = 0

func _ready() -> void:
	# Collect all direct Reel children so we are not brittle to scene order changes
	for child: Node in get_children():
		if child is Reel:
			_reels.append(child as Reel)
			child.spin_stopped.connect(_on_reel_spin_stopped)

func start_spin() -> void:
	if _state != State.READY:
		return
	if credits < bet_amount:
		return

	_stopped_reel_count = 0
	_state = State.SPINNING

	# Deduct bet before the reels move so credit state is always consistent
	credits -= bet_amount
	credits_changed.emit(credits)
	spin_initiated.emit()

	for reel: Reel in _reels:
		reel.spin()

	# Schedule staggered stop calls via SceneTree timers so each reel lands
	# slightly after the previous one — gives the classic slot-machine feel
	for i: int in range(_reels.size()):
		var delay: float = stop_stagger_delay * float(i)
		get_tree().create_timer(delay + 1.0).timeout.connect(
			func() -> void: _reels[i].stop()
		)

func add_credits(amount: int) -> void:
	credits += amount
	credits_changed.emit(credits)

func get_result_grid() -> Array:
	# Returns a 2D Array[Array[String]] — one inner array per reel, each entry is a visible symbol
	var grid: Array = []
	for reel: Reel in _reels:
		grid.append(reel.get_visible_symbols())
	return grid

func _on_reel_spin_stopped(_result: Array[String]) -> void:
	_stopped_reel_count += 1
	if _stopped_reel_count < _reels.size():
		return

	# All reels have landed; transition before emitting so listeners see EVALUATING state
	_state = State.EVALUATING
	var grid: Array = get_result_grid()
	all_reels_stopped.emit(grid)
	_evaluate_results(grid)

func _evaluate_results(grid: Array) -> void:
	# grid is Array[Array[String]]; rows are reels, columns are visible symbol positions
	# For each visible row across all reels, check the paytable for a matching combo
	if _reels.is_empty():
		_apply_payout(0)
		return

	var visible_rows: int = (_reels[0] as Reel).visible_symbol_count
	var total_payout: int = 0

	for row: int in range(visible_rows):
		# Build the symbol combination for this horizontal row
		var combo: Array[String] = []
		for reel_symbols: Array in grid:
			if row < reel_symbols.size():
				combo.append(reel_symbols[row] as String)

		var combo_key: String = ",".join(combo)
		if paytable.has(combo_key):
			var multiplier: int = paytable[combo_key] as int
			total_payout += bet_amount * multiplier

	_apply_payout(total_payout)

func _apply_payout(amount: int) -> void:
	_state = State.PAYING_OUT
	payout_calculated.emit(amount)

	if amount > 0:
		credits += amount
		credits_changed.emit(credits)

	_state = State.READY
