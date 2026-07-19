extends SceneTree

# Headless test: the live 8 DamageType .tres reproduce the authored 8x8 chart EXACTLY
# (type_chart_6x6_labeled.html, adopted 2026-06-28, extended to Light/Dark 2026-07-18). A regression
# lock so the chart that combat resolves against — and the TypeChartPanel renders — stays intentional.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_type_chart.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Order: Slashing, Piercing, Crushing, Storm, Mystic, Earth, Light, Dark.
	var types: Array[DamageType] = [
		load("res://combat/resources/types/slashing.tres"),
		load("res://combat/resources/types/piercing.tres"),
		load("res://combat/resources/types/crushing.tres"),
		load("res://combat/resources/types/storm.tres"),
		load("res://combat/resources/types/mystic.tres"),
		load("res://combat/resources/types/earth.tres"),
		load("res://combat/resources/types/light.tres"),
		load("res://combat/resources/types/dark.tres"),
	]
	# Expected matrix [attacker][defender], same order. Light/Dark are neutral (1.0) against every
	# existing type in both directions, and mutually 1.5x against each other.
	var M: Array = [
		[1.0,  1.25, 0.75, 1.0,  1.0,  1.25, 1.0, 1.0],  # Slashing
		[0.75, 1.0,  1.25, 1.0,  1.0,  0.75, 1.0, 1.0],  # Piercing
		[1.25, 0.75, 1.0,  1.0,  1.0,  1.0,  1.0, 1.0],  # Crushing
		[1.0,  1.0,  1.0,  1.0,  0.75, 1.25, 1.0, 1.0],  # Storm
		[1.25, 1.25, 0.5,  1.25, 1.0,  0.75, 1.0, 1.0],  # Mystic
		[1.0,  1.0,  1.25, 0.75, 1.25, 1.0,  1.0, 1.0],  # Earth
		[1.0,  1.0,  1.0,  1.0,  1.0,  1.0,  1.0, 1.5],  # Light
		[1.0,  1.0,  1.0,  1.0,  1.0,  1.0,  1.5, 1.0],  # Dark
	]
	var names: Array[String] = ["Slashing", "Piercing", "Crushing", "Storm", "Mystic", "Earth", "Light", "Dark"]
	for a: int in range(8):
		for d: int in range(8):
			var got: float = types[a].multiplier_against(types[d])
			_check(is_equal_approx(got, M[a][d]), "%s vs %s = ×%s (got ×%s)" % [names[a], names[d], M[a][d], got])

	# The enum identity of each loaded resource matches its slot (guards a mis-saved `type` field).
	for i: int in range(8):
		_check(types[i].type == i, "%s has enum index %d (got %d)" % [names[i], i, types[i].type])
	# Crushing keeps its inherent slow rider.
	_check(types[2].inherent_rider_id == &"slow", "Crushing keeps the &\"slow\" inherent rider")

	print(("TYPE CHART TEST PASSED" if _failures == 0 else "TYPE CHART TEST FAILED: %d" % _failures))
	quit(_failures)
