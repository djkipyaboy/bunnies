extends SceneTree

## FishingShadowGenerator: pure shadow-layout math for the Fishing mini-game's targeting phase
## (2026-08-01 gathering-profession-minigames spec section 3). Mirrors Wander's "caller supplies
## randomness" pattern for the deterministic core (make_shadow); generate() is the thin wrapper
## that supplies real randf()/randi() calls.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_check(FishingShadowGenerator.reel_count_for_bucket(&"small") == 1, "small bucket maps to 1 reel")
	_check(FishingShadowGenerator.reel_count_for_bucket(&"medium") == 3, "medium bucket maps to 3 reels")
	_check(FishingShadowGenerator.reel_count_for_bucket(&"large") == 5, "large bucket maps to 5 reels")

	var bounds := Rect2(0.0, 0.0, 200.0, 100.0)

	var small_shadow: Dictionary = FishingShadowGenerator.make_shadow(bounds, 0.0, 0.0, 0)
	_check(small_shadow["size_bucket"] == &"small", "bucket_index 0 maps to the small bucket")
	_check(bounds.has_point(small_shadow["position"]), "a shadow placed at fraction (0,0) still lands inside bounds (radius-inset)")

	var large_shadow: Dictionary = FishingShadowGenerator.make_shadow(bounds, 1.0, 1.0, 2)
	_check(large_shadow["size_bucket"] == &"large", "bucket_index 2 maps to the large bucket")
	_check(bounds.has_point(large_shadow["position"]), "a shadow placed at fraction (1,1) still lands inside bounds (radius-inset)")
	_check(large_shadow["radius"] > small_shadow["radius"], "a large-bucket shadow has a bigger radius than a small-bucket one")

	# generate() supplies real randomness -- prove over many calls that (a) every position stays
	# in bounds and (b) bucket variety actually appears (not always the same bucket).
	var seen_buckets: Dictionary = {}
	var any_out_of_bounds: bool = false
	for i in range(50):
		var shadows: Array[Dictionary] = FishingShadowGenerator.generate(bounds, 3, 6)
		if shadows.size() < 3 or shadows.size() > 6:
			any_out_of_bounds = true
		for shadow: Dictionary in shadows:
			seen_buckets[shadow["size_bucket"]] = true
			if not bounds.has_point(shadow["position"]):
				any_out_of_bounds = true
	_check(not any_out_of_bounds, "over 50 generate() calls, every shadow's count is within [3,6] and every position is in bounds")
	_check(seen_buckets.size() > 1, "over 50 generate() calls, more than one size bucket appears")

	print("ok FishingShadowGenerator smoke test complete")
	quit()
