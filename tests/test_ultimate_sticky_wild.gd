extends SceneTree

# Headless test: Sticky-Wild Ultimate — arm/fire/consume, ALL weapon reels forced crit for 2
# spins, then revert. Cost is the full Bonus Meter (cap 15) and NOTHING else.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_sticky_wild.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_pc() -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.weapon = w
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 15
	return c

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# --- Cannot fire while the meter is not armed ---
	var c: Combatant = _mk_pc()
	c.bonus_meter.value = c.bonus_meter.cap - 1
	_check(not c.fire_sticky_wild(c.weapon.reels.size(), 2), "cannot fire below cap")
	_check(c.sticky_wild_spins_remaining == 0, "no wild armed on failed fire")
	_check(c.wild_reel_indices() == [], "no wild reels on failed fire (got %s)" % str(c.wild_reel_indices()))

	# --- Firing consumes the full meter and arms ALL weapon reels ---
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.bonus_meter.is_armed(), "meter armed at cap 15")
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 2), "fire succeeds when armed")
	_check(c.bonus_meter.value == 0, "fire consumes the meter (got %d)" % c.bonus_meter.value)
	_check(c.sticky_wild_count == 3, "all 3 weapon reels wild after firing (got %d)" % c.sticky_wild_count)
	_check(c.wild_reel_indices() == [0, 1, 2], "every weapon reel is wild after firing (got %s)" % str(c.wild_reel_indices()))

	# --- Resolver forces crit-success on EVERY wild reel ---
	var resolver: CombatResolver = CombatResolver.new()
	c.begin_turn()
	var a1: Array = resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, null, c.wild_reel_indices())
	for i: int in range(a1.size()):
		_check(a1[i].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "reel %d forces crit-success (spin 1)" % i)
	c.consume_wild_spin()
	_check(c.sticky_wild_spins_remaining == 1, "1 wild spin left (got %d)" % c.sticky_wild_spins_remaining)
	_check(c.wild_reel_indices() == [0, 1, 2], "still all reels wild between spins (got %s)" % str(c.wild_reel_indices()))

	# --- Second spin still wild on all reels, then it reverts ---
	c.begin_turn()
	var a2: Array = resolver.resolve_combat_phase(c.turn_reels, c.weapon.base_damage, null, c.wild_reel_indices())
	for i: int in range(a2.size()):
		_check(a2[i].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "reel %d forces crit-success (spin 2)" % i)
	c.consume_wild_spin()
	_check(c.sticky_wild_spins_remaining == 0, "wild exhausted (got %d)" % c.sticky_wild_spins_remaining)
	_check(c.wild_reel_indices() == [], "no wild reels after exhaustion (got %s)" % str(c.wild_reel_indices()))
	_check(c.sticky_wild_count == 0, "wild count cleared on exhaustion (got %d)" % c.sticky_wild_count)

	# --- Firing never touches the ResourcePool (independent economies) ---
	var c2: Combatant = _mk_pc()
	c2.resource_pool = ResourcePool.new(); c2.resource_pool.max_stamina = 5; c2.resource_pool.stamina = 4
	c2.bonus_meter.value = c2.bonus_meter.cap
	c2.fire_sticky_wild(c2.weapon.reels.size(), 2)
	_check(c2.resource_pool.stamina == 4, "fire does not spend stamina (got %d)" % c2.resource_pool.stamina)

	print(("STICKY WILD TEST PASSED" if _failures == 0 else "STICKY WILD TEST FAILED: %d" % _failures))
	quit(_failures)
