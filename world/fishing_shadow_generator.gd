class_name FishingShadowGenerator
extends RefCounted

## Pure/static shadow-layout math for the Fishing mini-game's targeting phase (2026-08-01
## gathering-profession-minigames spec section 3). Mirrors Wander's "caller supplies randomness"
## pattern: make_shadow() is a pure function of explicit inputs; generate() is the thin wrapper
## that supplies real randomness for FishingPanel's real call sites.

const SIZE_BUCKETS: Array[StringName] = [&"small", &"medium", &"large"]

## [ASSUMPTION] reel-count-per-bucket mapping (spec section 3), tuned by playtest.
const REEL_COUNT_FOR_BUCKET: Dictionary = {&"small": 1, &"medium": 3, &"large": 5}

## [ASSUMPTION] radius-per-bucket (visual + hit-detection size), tuned by playtest.
const RADIUS_FOR_BUCKET: Dictionary = {&"small": 16.0, &"medium": 24.0, &"large": 32.0}

static func reel_count_for_bucket(bucket: StringName) -> int:
	return REEL_COUNT_FOR_BUCKET.get(bucket, 1)

## Returns one shadow's {"position": Vector2, "size_bucket": StringName, "radius": float}, placed
## within [param bounds] using the explicit [param x_fraction]/[param y_fraction] (each clamped to
## 0.0-1.0, caller-supplied randomness) and [param bucket_index] (caller-supplied index into
## SIZE_BUCKETS, clamped). The radius inset keeps the shadow's full circle inside bounds.
static func make_shadow(bounds: Rect2, x_fraction: float, y_fraction: float, bucket_index: int) -> Dictionary:
	var bucket: StringName = SIZE_BUCKETS[clampi(bucket_index, 0, SIZE_BUCKETS.size() - 1)]
	var radius: float = RADIUS_FOR_BUCKET[bucket]
	var usable_w: float = maxf(bounds.size.x - radius * 2.0, 0.0)
	var usable_h: float = maxf(bounds.size.y - radius * 2.0, 0.0)
	var position: Vector2 = bounds.position + Vector2(
		radius + clampf(x_fraction, 0.0, 1.0) * usable_w,
		radius + clampf(y_fraction, 0.0, 1.0) * usable_h)
	return {"position": position, "size_bucket": bucket, "radius": radius}

## Generates a fresh, freshly-randomized layout every call -- [ASSUMPTION] shadow count between
## [param min_count] and [param max_count] inclusive, tuned by playtest.
static func generate(bounds: Rect2, min_count: int, max_count: int) -> Array[Dictionary]:
	var count: int = randi_range(min_count, max_count)
	var shadows: Array[Dictionary] = []
	for i in range(count):
		shadows.append(make_shadow(bounds, randf(), randf(), randi() % SIZE_BUCKETS.size()))
	return shadows
