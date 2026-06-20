extends SceneTree

# Headless test for payline reward math: BonusMeter.add_flat, ResourcePool.refund, and the crit-line
# bonus-damage formula ceil(base * length/3 * type_mult). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_payline_rewards.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else:
		_failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

# Mirror of the orchestrator's crit-line bonus formula (kept here to lock the math).
func _crit_bonus(base: float, length: int, type_mult: float) -> int:
	return ceili(base * (float(length) / 3.0) * type_mult)

func _initialize() -> void:
	# Length scaling with round-up (base 10, type x1.0): L2=7, L3=10, L4=14, L5=17.
	_check(_crit_bonus(10.0, 2, 1.0) == 7, "L2 -> ceil(6.667)=7 (got %d)" % _crit_bonus(10.0, 2, 1.0))
	_check(_crit_bonus(10.0, 3, 1.0) == 10, "L3 -> 10 (got %d)" % _crit_bonus(10.0, 3, 1.0))
	_check(_crit_bonus(10.0, 4, 1.0) == 14, "L4 -> ceil(13.334)=14 (got %d)" % _crit_bonus(10.0, 4, 1.0))
	_check(_crit_bonus(10.0, 5, 1.0) == 17, "L5 -> ceil(16.667)=17 (got %d)" % _crit_bonus(10.0, 5, 1.0))
	_check(_crit_bonus(10.0, 3, 1.25) == 13, "L3 x1.25 -> ceil(12.5)=13 (got %d)" % _crit_bonus(10.0, 3, 1.25))

	# BonusMeter.add_flat clamps at cap and signals.
	var m: BonusMeter = BonusMeter.new()
	m.cap = 10; m.value = 9
	m.add_flat(1)
	_check(m.value == 10, "add_flat to cap (got %d)" % m.value)
	m.add_flat(5)
	_check(m.value == 10, "add_flat clamps at cap (got %d)" % m.value)

	# ResourcePool.refund adds, clamped at max.
	var p: ResourcePool = ResourcePool.new()
	p.max_stamina = 5; p.stamina = 4
	p.refund({&"stamina": 1})
	_check(p.stamina == 5, "refund +1 -> 5 (got %d)" % p.stamina)
	p.refund({&"stamina": 3})
	_check(p.stamina == 5, "refund clamps at max (got %d)" % p.stamina)

	print(("PAYLINE REWARDS TEST PASSED" if _failures == 0 else "PAYLINE REWARDS TEST FAILED: %d" % _failures))
	quit(_failures)
