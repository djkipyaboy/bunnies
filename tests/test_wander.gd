extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# angle = 0 means "straight along +X"; distance_fraction = 1.0 means "at the full radius".
	var target_east: Vector2 = Wander.random_target(Vector2(100, 100), 50.0, 0.0, 1.0)
	_check(target_east.is_equal_approx(Vector2(150, 100)), "random_target at angle 0, full radius, lands due east")

	# distance_fraction = 0.0 always returns the origin regardless of angle.
	var target_origin: Vector2 = Wander.random_target(Vector2(100, 100), 50.0, 1.234, 0.0)
	_check(target_origin.is_equal_approx(Vector2(100, 100)), "random_target at distance_fraction 0 returns the origin")

	# distance_fraction is clamped to [0, 1] even if given an out-of-range value.
	var target_clamped: Vector2 = Wander.random_target(Vector2(0, 0), 50.0, 0.0, 5.0)
	_check(target_clamped.is_equal_approx(Vector2(50, 0)), "random_target clamps distance_fraction above 1.0")

	# Property-style check: for many random samples, the picked point never leaves the leash radius.
	var origin := Vector2(200, 200)
	var radius: float = 40.0
	var all_within_radius: bool = true
	for i in range(200):
		var angle: float = randf_range(0.0, TAU)
		var fraction: float = randf()
		var sample: Vector2 = Wander.random_target(origin, radius, angle, fraction)
		if sample.distance_to(origin) > radius + 0.001:
			all_within_radius = false
			break
	_check(all_within_radius, "200 random random_target samples all stay within the leash radius")
	quit()
