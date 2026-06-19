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

	print(("EFFECT TEST PASSED" if _failures == 0 else "EFFECT TEST FAILED: %d" % _failures))
	quit(_failures)
