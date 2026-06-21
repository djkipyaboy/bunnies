extends SceneTree

# Headless test: BLEED lifecycle through the bearer's End sequence (the order combat.gd uses:
# apply DoT damage, THEN tick durations). Validates 3 ticks of damage then expiry, and stacking.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_bleed_lifecycle.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

# Mirrors combat.gd: sum each active DoT's dot_damage, apply it, THEN tick durations (on_end).
func _end_phase(c: Combatant) -> int:
	var dmg: int = 0
	for e: Effect in c.active_effects:
		if e.kind == Effect.Kind.DAMAGE_OVER_TIME:
			dmg += e.dot_damage()
	if dmg > 0:
		c.take_damage(dmg)
	c.tick_effects()
	return dmg

func _bleed(base: float) -> Effect:
	var b: Effect = EffectLibrary.make(&"bleed")
	b.dot_base_damage = base
	return b

func _initialize() -> void:
	# 1-stack bleed off a base-8 weapon: 4/turn for 3 of the bearer's End phases, then gone.
	var c: Combatant = Combatant.new()
	c.max_hp = 100; c.hp = 100
	c.attach_effect(_bleed(8.0))
	_check(_end_phase(c) == 4 and c.hp == 96, "turn 1: bleed 4 (hp 96, got %d)" % c.hp)
	_check(_end_phase(c) == 4 and c.hp == 92, "turn 2: bleed 4 (hp 92, got %d)" % c.hp)
	_check(_end_phase(c) == 4 and c.hp == 88, "turn 3: bleed 4 (hp 88, got %d)" % c.hp)
	_check(c.active_effects.is_empty(), "bleed expired after 3 ticks")
	_check(_end_phase(c) == 0 and c.hp == 88, "turn 4: no bleed left (hp 88, got %d)" % c.hp)

	# Re-applying before expiry stacks (to 3) and refreshes duration; 3 stacks @ base 8 = 10/turn.
	var d: Combatant = Combatant.new()
	d.max_hp = 100; d.hp = 100
	d.attach_effect(_bleed(8.0))   # 1 stack
	d.attach_effect(_bleed(8.0))   # 2 stacks
	d.attach_effect(_bleed(8.0))   # 3 stacks (cap), duration refreshed to 3
	_check(_end_phase(d) == 10 and d.hp == 90, "3-stack bleed = 10/turn (hp 90, got %d)" % d.hp)

	print(("BLEED LIFECYCLE TEST PASSED" if _failures == 0 else "BLEED LIFECYCLE TEST FAILED: %d" % _failures))
	quit(_failures)
