extends SceneTree

# Headless test: BLEED DoT (spec §4B) — dot_damage math (round up) + stacking via attach_effect.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_bleed.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Library returns a DoT template with the 50/80/115% fractions.
	var e: Effect = EffectLibrary.make(&"bleed")
	_check(e != null and e.kind == Effect.Kind.DAMAGE_OVER_TIME, "bleed is a DAMAGE_OVER_TIME effect")
	_check(e.duration == 3 and e.max_stacks == 3, "bleed: 3 turns, max 3 stacks")
	_check(e.beneficial == false, "bleed is a debuff")

	# dot_damage at weapon base 8, rounding UP: 1->ceil(4.0)=4, 2->ceil(6.4)=7, 3->ceil(9.2)=10.
	e.dot_base_damage = 8.0
	e.stacks = 1
	_check(e.dot_damage() == 4, "1 stack @ base 8 = ceil(4.0) = 4 (got %d)" % e.dot_damage())
	e.stacks = 2
	_check(e.dot_damage() == 7, "2 stacks @ base 8 = ceil(6.4) = 7 (got %d)" % e.dot_damage())
	e.stacks = 3
	_check(e.dot_damage() == 10, "3 stacks @ base 8 = ceil(9.2) = 10 (got %d)" % e.dot_damage())

	# A non-DoT effect returns 0.
	_check(EffectLibrary.make(&"slow").dot_damage() == 0, "slow (INITIATIVE_MOD) dot_damage = 0")

	# Stacking via Combatant.attach_effect: merge by id, grow stacks to cap 3, refresh duration.
	var c: Combatant = Combatant.new()
	for i: int in range(4):  # apply 4 times; cap at 3 stacks
		var b: Effect = EffectLibrary.make(&"bleed")
		b.dot_base_damage = 8.0
		c.attach_effect(b)
	var active: Effect = null
	for x: Effect in c.active_effects:
		if x.id == &"bleed": active = x
	_check(active != null, "bleed attached")
	_check(active.stacks == 3, "stacks capped at 3 after 4 applications (got %d)" % active.stacks)
	_check(active.duration == 3, "duration refreshed to 3 (got %d)" % active.duration)
	_check(active.dot_damage() == 10, "stacked bleed deals 10/turn @ base 8 (got %d)" % active.dot_damage())

	print(("BLEED TEST PASSED" if _failures == 0 else "BLEED TEST FAILED: %d" % _failures))
	quit(_failures)
