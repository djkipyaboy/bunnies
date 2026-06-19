extends SceneTree

# Headless unit test for ResourcePool (DESIGN.md §10 Dec 6; ARCHITECTURE §7).
# Stamina-only for the prototype. Run:
# Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_resource_pool.gd

var _failures: int = 0
var _changed_count: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _on_pool_changed(_kind: StringName, _value: int, _max: int) -> void:
	_changed_count += 1

func _mk() -> ResourcePool:
	var p: ResourcePool = ResourcePool.new()
	p.max_stamina = 5
	p.stamina = 3
	p.regen_per_turn = 1
	return p

func _initialize() -> void:
	var p: ResourcePool = _mk()
	_check(p.can_afford({&"stamina": 2}), "can afford 2 of 3")
	_check(not p.can_afford({&"stamina": 4}), "cannot afford 4 of 3")

	p.pool_changed.connect(_on_pool_changed)

	# --- spend deducts and signals ---
	_check(p.spend({&"stamina": 2}), "spend(2) succeeds")
	_check(p.stamina == 1, "stamina 3 -> 1 (got %d)" % p.stamina)
	_check(_changed_count == 1, "pool_changed fired on spend (got %d)" % _changed_count)

	# --- spend refuses when short: no mutation, no signal ---
	_check(not p.spend({&"stamina": 2}), "spend(2) refused at stamina 1")
	_check(p.stamina == 1, "stamina unchanged after refused spend (got %d)" % p.stamina)
	_check(_changed_count == 1, "no signal on refused spend (got %d)" % _changed_count)

	# --- regen adds and clamps at max ---
	p.regen()
	_check(p.stamina == 2, "regen +1 -> 2 (got %d)" % p.stamina)
	p.stamina = 5
	p.regen()
	_check(p.stamina == 5, "regen clamps at max 5 (got %d)" % p.stamina)

	print(("RESOURCE POOL TEST PASSED" if _failures == 0 else "RESOURCE POOL TEST FAILED: %d" % _failures))
	quit(_failures)
