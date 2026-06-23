extends SceneTree

# Headless test: apply_stats derives max_mana = base_max_mana + Focus and clamps current mana. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_derivation.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	var s: Stats = Stats.new(); s.focus = 6
	c.base_stats = s
	c.base_max_mana = 9
	c.base_max_stamina = 0
	c.resource_pool = ResourcePool.new()
	c.resource_pool.mana = 15   # seeded "full" — should clamp to max after derivation
	c.apply_stats()
	_check(c.resource_pool.max_mana == 15, "max_mana = 9 base + 6 Focus = 15 (got %d)" % c.resource_pool.max_mana)
	_check(c.resource_pool.mana == 15, "mana clamped to 15 (got %d)" % c.resource_pool.mana)

	# Lower Focus lowers the cap and clamps current mana down.
	var c2: Combatant = Combatant.new()
	var s2: Stats = Stats.new(); s2.focus = 2
	c2.base_stats = s2
	c2.base_max_mana = 9
	c2.resource_pool = ResourcePool.new()
	c2.resource_pool.mana = 15
	c2.apply_stats()
	_check(c2.resource_pool.max_mana == 11, "max_mana = 9 + 2 = 11 (got %d)" % c2.resource_pool.max_mana)
	_check(c2.resource_pool.mana == 11, "mana clamped down to 11 (got %d)" % c2.resource_pool.mana)

	print(("MANA DERIVATION TEST PASSED" if _failures == 0 else "MANA DERIVATION TEST FAILED: %d" % _failures))
	quit(_failures)
