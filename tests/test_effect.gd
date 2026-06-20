extends SceneTree

# Headless unit test for Effect + EffectLibrary (DESIGN.md §4.1, §4.6; ARCHITECTURE §7).
# Run: Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_effect.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _initialize() -> void:
	# --- EffectLibrary builds the Slow rider with the [ASSUMPTION] values ---
	var slow: Effect = EffectLibrary.make(&"slow")
	_check(slow != null, "library returns an Effect for &\"slow\"")
	_check(slow.kind == Effect.Kind.INITIATIVE_MOD, "slow is an INITIATIVE_MOD")
	_check(is_equal_approx(slow.magnitude, -20.0), "slow magnitude is -20 (got %s)" % str(slow.magnitude))
	_check(slow.duration == 2, "slow duration is 2 (got %d)" % slow.duration)
	_check(slow.id == &"slow", "slow id round-trips")

	# --- Unknown id yields null ---
	_check(EffectLibrary.make(&"nonesuch") == null, "unknown id -> null")

	# --- Each make() is independent (no shared mutable state) ---
	var a: Effect = EffectLibrary.make(&"slow")
	var b: Effect = EffectLibrary.make(&"slow")
	a.tick()
	_check(a.duration == 1 and b.duration == 2, "two builds are independent (a=%d, b=%d)" % [a.duration, b.duration])

	# --- tick() counts down; is_expired() at 0 ---
	var e: Effect = EffectLibrary.make(&"slow")
	_check(not e.is_expired(), "fresh effect not expired (duration %d)" % e.duration)
	e.tick(); e.tick()
	_check(e.duration == 0 and e.is_expired(), "expired after 2 ticks (duration %d)" % e.duration)

	# --- Combatant: attaching Slow lowers derived current_initiative; expiry restores it ---
	var c: Combatant = Combatant.new()
	c.display_name = "Martin"
	c.max_hp = 40
	c.base_initiative = 50
	c.recompute_initiative()
	_check(c.current_initiative == 50, "current_initiative derives from base (got %d)" % c.current_initiative)

	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.current_initiative == 30, "Slow -20 -> current_initiative 30 (got %d)" % c.current_initiative)

	c.on_end()  # tick 1: duration 2 -> 1, still attached
	_check(c.current_initiative == 30, "still slowed after 1 turn (got %d)" % c.current_initiative)
	_check(c.active_effects.size() == 1, "slow still attached after 1 tick (got %d)" % c.active_effects.size())

	c.on_end()  # tick 2: duration 1 -> 0, expires and detaches
	_check(c.current_initiative == 50, "initiative restored after Slow expires (got %d)" % c.current_initiative)
	_check(c.active_effects.is_empty(), "slow detached on expiry (got %d)" % c.active_effects.size())

	# --- Two combatants don't share a duration counter ---
	var c1: Combatant = Combatant.new(); c1.base_initiative = 50; c1.recompute_initiative()
	var c2: Combatant = Combatant.new(); c2.base_initiative = 50; c2.recompute_initiative()
	c1.attach_effect(EffectLibrary.make(&"slow"))
	c2.attach_effect(EffectLibrary.make(&"slow"))
	c1.on_end()
	_check(c2.active_effects[0].duration == 2, "c2 slow unaffected by c1 tick (got %d)" % c2.active_effects[0].duration)

	# --- on_upkeep regenerates the resource pool when present ---
	var rc: Combatant = Combatant.new()
	rc.base_initiative = 50
	rc.resource_pool = ResourcePool.new()
	rc.resource_pool.max_stamina = 5
	rc.resource_pool.stamina = 1
	rc.resource_pool.regen_per_turn = 1
	rc.on_upkeep()
	_check(rc.resource_pool.stamina == 2, "on_upkeep regens stamina 1 -> 2 (got %d)" % rc.resource_pool.stamina)

	# --- on_upkeep is safe when no pool is attached ---
	var np: Combatant = Combatant.new()
	np.base_initiative = 50
	np.on_upkeep()
	_check(np.resource_pool == null, "on_upkeep no-ops without a pool")

	# --- Stacking model: effective_magnitude by stack count, cap, and EffectLibrary schedule ---
	var s1: Effect = EffectLibrary.make(&"slow")
	_check(s1.max_stacks == 3, "slow max_stacks == 3 (got %d)" % s1.max_stacks)
	_check(s1.stack_magnitudes == [-20.0, -10.0, -5.0], "slow stack schedule (got %s)" % str(s1.stack_magnitudes))
	_check(s1.stacks == 1, "fresh slow starts at 1 stack (got %d)" % s1.stacks)
	_check(is_equal_approx(s1.effective_magnitude(), -20.0), "1 stack -> -20 (got %s)" % str(s1.effective_magnitude()))
	_check(s1.add_stack(), "2nd add_stack succeeds")
	_check(is_equal_approx(s1.effective_magnitude(), -30.0), "2 stacks -> -30 (got %s)" % str(s1.effective_magnitude()))
	_check(s1.add_stack(), "3rd add_stack succeeds")
	_check(is_equal_approx(s1.effective_magnitude(), -35.0), "3 stacks -> -35 (got %s)" % str(s1.effective_magnitude()))
	_check(not s1.add_stack(), "4th add_stack refused at cap")
	_check(s1.stacks == 3, "stacks capped at 3 (got %d)" % s1.stacks)
	_check(is_equal_approx(s1.effective_magnitude(), -35.0), "capped magnitude stays -35 (got %s)" % str(s1.effective_magnitude()))

	# --- Non-stacking effect: effective_magnitude is the flat magnitude; cannot add a stack ---
	var flat: Effect = Effect.new()
	flat.kind = Effect.Kind.INITIATIVE_MOD
	flat.magnitude = -7.0
	_check(is_equal_approx(flat.effective_magnitude(), -7.0), "non-stacking effective = flat magnitude (got %s)" % str(flat.effective_magnitude()))
	_check(not flat.add_stack(), "non-stacking add_stack refused (max_stacks 1)")

	# --- attach_effect merges a stacking debuff by id: diminishing, capped, never a 2nd instance ---
	var sc: Combatant = Combatant.new()
	sc.base_initiative = 60
	sc.recompute_initiative()
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.active_effects.size() == 1 and sc.current_initiative == 40, "1st slow: init 40, 1 effect (init %d, n %d)" % [sc.current_initiative, sc.active_effects.size()])
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.active_effects.size() == 1 and sc.current_initiative == 30, "2nd slow merges: init 30, still 1 effect (init %d, n %d)" % [sc.current_initiative, sc.active_effects.size()])
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.current_initiative == 25, "3rd slow: -35 -> init 25 (got %d)" % sc.current_initiative)
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.current_initiative == 25 and sc.active_effects.size() == 1, "4th slow capped: init 25, 1 effect (init %d)" % sc.current_initiative)
	_check(sc.active_effects[0].stacks == 3, "merged effect capped at 3 stacks (got %d)" % sc.active_effects[0].stacks)

	# --- re-applying refreshes the duration to the incoming value ---
	sc.active_effects[0].duration = 1   # simulate one tick elapsed
	sc.attach_effect(EffectLibrary.make(&"slow"))
	_check(sc.active_effects[0].duration == 2, "re-apply refreshes duration to 2 (got %d)" % sc.active_effects[0].duration)

	# --- non-stacking effect also merges by id (refresh only, no doubling, no 2nd instance) ---
	var nc: Combatant = Combatant.new()
	nc.base_initiative = 50
	nc.recompute_initiative()
	var w1: Effect = Effect.new()
	w1.id = &"weaken"; w1.kind = Effect.Kind.INITIATIVE_MOD; w1.magnitude = -5.0; w1.duration = 2; w1.max_stacks = 1
	nc.attach_effect(w1)
	var w2: Effect = Effect.new()
	w2.id = &"weaken"; w2.kind = Effect.Kind.INITIATIVE_MOD; w2.magnitude = -5.0; w2.duration = 2; w2.max_stacks = 1
	nc.attach_effect(w2)
	_check(nc.active_effects.size() == 1 and nc.current_initiative == 45, "non-stacking weaken merges: 1 effect, -5 not -10 (init %d, n %d)" % [nc.current_initiative, nc.active_effects.size()])

	# --- distinct ids attach as separate effects ---
	nc.attach_effect(EffectLibrary.make(&"slow"))
	_check(nc.active_effects.size() == 2 and nc.current_initiative == 25, "distinct id (slow) adds a 2nd effect: init 25 (n %d, init %d)" % [nc.active_effects.size(), nc.current_initiative])

	# --- Effect polarity + Inspirational ---
	var slow_p: Effect = EffectLibrary.make(&"slow")
	_check(not slow_p.beneficial, "slow is a debuff (beneficial == false)")
	var insp: Effect = EffectLibrary.make(&"inspirational")
	_check(insp != null, "library builds Inspirational")
	_check(insp.kind == Effect.Kind.INITIATIVE_MOD, "inspirational is INITIATIVE_MOD")
	_check(is_equal_approx(insp.magnitude, 5.0), "inspirational +5 init (got %s)" % str(insp.magnitude))
	_check(insp.duration == 2, "inspirational duration 2 (got %d)" % insp.duration)
	_check(insp.max_stacks == 1, "inspirational non-stacking (got %d)" % insp.max_stacks)
	_check(insp.beneficial, "inspirational is a buff (beneficial == true)")

	print(("EFFECT TEST PASSED" if _failures == 0 else "EFFECT TEST FAILED: %d" % _failures))
	quit(_failures)
