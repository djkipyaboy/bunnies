extends SceneTree

# Headless unit test for BonusMeter (DESIGN.md §4.9).
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_bonus_meter.gd
# NOTE: capture signal results via member vars + method handlers — GDScript lambdas capture
# outer locals BY VALUE and can't mutate the enclosing scope.

var _failures: int = 0
var _meter_changed_count: int = 0
var _last_value: int = -1
var _last_cap: int = -1
var _armed_count: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _on_meter_changed(value: int, cap: int) -> void:
	_meter_changed_count += 1
	_last_value = value
	_last_cap = cap

func _on_meter_armed() -> void:
	_armed_count += 1

func _make_meter(floor_val: int = 3, cap_val: int = 10) -> BonusMeter:
	var m: BonusMeter = BonusMeter.new()
	m.cap = cap_val
	m.floor = floor_val
	return m

func _initialize() -> void:
	# --- charge() accumulates per default weights (critfail 0, fail 0, neutral 1, success 2, critsuccess 3) ---
	var m: BonusMeter = _make_meter()
	m.charge(ReelFace.ResultTier.SUCCESS)        # +2
	m.charge(ReelFace.ResultTier.CRIT_SUCCESS)   # +3
	_check(m.value == 5, "success(+2) + crit_success(+3) = 5 (got %d)" % m.value)
	m.charge(ReelFace.ResultTier.NEUTRAL)        # +1
	m.charge(ReelFace.ResultTier.FAILURE)        # +0
	m.charge(ReelFace.ResultTier.CRIT_FAILURE)   # +0
	_check(m.value == 6, "neutral(+1), failures(+0) -> 6 (got %d)" % m.value)

	# --- charge() clamps at cap and arms ---
	var m2: BonusMeter = _make_meter()
	for i: int in range(10):
		m2.charge(ReelFace.ResultTier.CRIT_SUCCESS)  # 10 * +3, must clamp at cap 10
	_check(m2.value == 10, "charge clamps at cap 10 (got %d)" % m2.value)
	_check(m2.is_armed(), "is_armed() true at cap")

	# --- signals: meter_changed fires with (value, cap); meter_armed fires once on reaching cap ---
	var m3: BonusMeter = _make_meter()
	m3.meter_changed.connect(_on_meter_changed)
	m3.meter_armed.connect(_on_meter_armed)
	m3.charge(ReelFace.ResultTier.SUCCESS)       # value 2
	_check(_meter_changed_count == 1, "meter_changed fired once (got %d)" % _meter_changed_count)
	_check(_last_value == 2 and _last_cap == 10, "meter_changed payload (2,10) (got %d,%d)" % [_last_value, _last_cap])
	for i: int in range(4):
		m3.charge(ReelFace.ResultTier.CRIT_SUCCESS)  # 2 -> 5 -> 8 -> 10(clamp) -> 10
	_check(_armed_count == 1, "meter_armed fired exactly once (got %d)" % _armed_count)

	# --- resolve_post_combat(): floor/full-carry rule (DESIGN.md §4.9) ---
	var below: BonusMeter = _make_meter(3, 10); below.value = 2
	below.resolve_post_combat()
	_check(below.value == 0, "end below floor (2<3) resets to 0 (got %d)" % below.value)

	var mid: BonusMeter = _make_meter(3, 10); mid.value = 5
	mid.resolve_post_combat()
	_check(mid.value == 3, "end at/above floor (5) resets to floor 3 (got %d)" % mid.value)

	var atfloor: BonusMeter = _make_meter(3, 10); atfloor.value = 3
	atfloor.resolve_post_combat()
	_check(atfloor.value == 3, "end exactly at floor (3) stays 3 (got %d)" % atfloor.value)

	var full: BonusMeter = _make_meter(3, 10); full.value = 10
	full.resolve_post_combat()
	_check(full.value == 10, "end full (10) carries full (got %d)" % full.value)

	# --- consume() empties the meter ---
	var spent: BonusMeter = _make_meter(3, 10); spent.value = 10
	spent.consume()
	_check(spent.value == 0, "consume() empties to 0 (got %d)" % spent.value)

	print(("BONUS METER TEST PASSED" if _failures == 0 else "BONUS METER TEST FAILED: %d" % _failures))
	quit(_failures)
