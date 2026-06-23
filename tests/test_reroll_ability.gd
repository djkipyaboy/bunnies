extends SceneTree

# Headless: Chancer reroll/gamble commit bookkeeping (spend, flags, refund, clear). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_reroll_ability.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# stage_reroll spends stamina and sets the pending flag.
	var c: Combatant = Combatant.new()
	c.resource_pool = ResourcePool.new(); c.resource_pool.stamina = 7; c.resource_pool.max_stamina = 7
	_check(c.stage_reroll(4), "stage_reroll succeeds with 7 stamina")
	_check(c.resource_pool.stamina == 3, "spent 4 -> 3 left (got %d)" % c.resource_pool.stamina)
	_check(c.reroll_pending and c.reroll_cost == 4, "reroll_pending set, cost recorded")

	# refund_reroll gives it back and clears.
	c.refund_reroll()
	_check(c.resource_pool.stamina == 7, "refund -> 7 (got %d)" % c.resource_pool.stamina)
	_check(not c.reroll_pending and c.reroll_cost == 0, "reroll state cleared after refund")

	# unaffordable stage_reroll changes nothing.
	var d: Combatant = Combatant.new()
	d.resource_pool = ResourcePool.new(); d.resource_pool.stamina = 2; d.resource_pool.max_stamina = 7
	_check(not d.stage_reroll(4), "stage_reroll fails with 2 stamina")
	_check(d.resource_pool.stamina == 2 and not d.reroll_pending, "no spend, no flag on failure")

	# fire_wildcard_gamble consumes an armed meter.
	var e: Combatant = Combatant.new()
	e.bonus_meter = BonusMeter.new(); e.bonus_meter.cap = 30; e.bonus_meter.floor = 3
	e.bonus_meter.add_flat(30)  # arm it
	_check(e.bonus_meter.is_armed(), "meter armed")
	_check(e.fire_wildcard_gamble(), "fire_wildcard_gamble consumes armed meter")
	_check(e.wildcard_gamble_pending, "gamble pending set")
	_check(not e.bonus_meter.is_armed(), "meter consumed")
	e.clear_reroll_state()
	_check(not e.wildcard_gamble_pending, "clear_reroll_state clears gamble flag")

	# fire_wildcard_gamble with no meter -> false.
	var f: Combatant = Combatant.new()
	f.bonus_meter = BonusMeter.new(); f.bonus_meter.cap = 30; f.bonus_meter.floor = 3
	_check(not f.fire_wildcard_gamble(), "no fire without armed meter")

	print(("REROLL ABILITY TEST PASSED" if _failures == 0 else "REROLL ABILITY TEST FAILED: %d" % _failures))
	quit(_failures)
