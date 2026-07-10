extends SceneTree

# Headless test: Focus adds to the per-Upkeep resource regen tick (spec §5.3), on top of its
# existing max-pool role. Derivation must be idempotent (apply_stats can run more than once).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_focus_regen.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.base_max_stamina = 5
	c.base_stamina_regen = 1
	c.resource_pool = ResourcePool.new()
	var s: Stats = Stats.new(); s.focus = 6
	c.base_stats = s
	c.apply_stats()
	# regen = base 1 + floor(6 * 0.5) = 1 + 3 = 4.
	_check(c.resource_pool.regen_per_turn == 4, "stamina regen = 1 base + Focus 6 bonus 3 = 4 (got %d)" % c.resource_pool.regen_per_turn)

	# Idempotency: calling apply_stats() again must not compound the bonus.
	c.apply_stats()
	_check(c.resource_pool.regen_per_turn == 4, "apply_stats is idempotent for regen (got %d)" % c.resource_pool.regen_per_turn)

	# Mana rail, same derivation.
	var m: Combatant = Combatant.new()
	m.base_max_mana = 9
	m.base_mana_regen = 1
	m.resource_pool = ResourcePool.new()
	var s2: Stats = Stats.new(); s2.focus = 6
	m.base_stats = s2
	m.apply_stats()
	_check(m.resource_pool.mana_regen_per_turn == 4, "mana regen = 1 base + Focus 6 bonus 3 = 4 (got %d)" % m.resource_pool.mana_regen_per_turn)

	# 0 Focus -> base regen unchanged.
	var zero: Combatant = Combatant.new()
	zero.base_max_stamina = 5
	zero.base_stamina_regen = 2
	zero.resource_pool = ResourcePool.new()
	zero.apply_stats()
	_check(zero.resource_pool.regen_per_turn == 2, "0 Focus -> base regen unchanged (got %d)" % zero.resource_pool.regen_per_turn)

	print(("FOCUS REGEN TEST PASSED" if _failures == 0 else "FOCUS REGEN TEST FAILED: %d" % _failures))
	quit(_failures)
