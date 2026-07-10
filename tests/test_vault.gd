extends SceneTree

# Headless test: Vault's finite, per-tab, expandable capacity (spec §4.2). No Quest tab exists —
# quest items are per-playthrough and never cross the party<->bank boundary.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_vault.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var v: Vault = Vault.new()
	_check(v.capacity_for(&"gear") == 0, "no tab capacity until expanded (got %d)" % v.capacity_for(&"gear"))

	v.tab_capacity[&"gear"] = 10
	_check(v.capacity_for(&"gear") == 10, "capacity reads back after expansion (got %d)" % v.capacity_for(&"gear"))
	_check(v.can_add(&"gear", v.gear), "empty gear list under capacity 10 can add")

	for i: int in range(10):
		v.gear.append(Gear.new())
	_check(not v.can_add(&"gear", v.gear), "gear list at capacity 10 refuses further adds")

	# Expansion (the dual-sink economy) simply raises the number — content/costs are out of scope.
	v.tab_capacity[&"gear"] = 11
	_check(v.can_add(&"gear", v.gear), "expanding the tab immediately allows one more add")

	# Materials/Reel-Mods tabs are independent capacities.
	v.tab_capacity[&"materials"] = 5
	_check(v.capacity_for(&"materials") == 5, "materials tab has its own independent capacity")
	_check(v.capacity_for(&"reel_mods") == 0, "reel_mods tab still unexpanded (got %d)" % v.capacity_for(&"reel_mods"))

	print(("VAULT TEST PASSED" if _failures == 0 else "VAULT TEST FAILED: %d" % _failures))
	quit(_failures)
