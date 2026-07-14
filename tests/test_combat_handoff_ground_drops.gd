extends SceneTree

# Headless test: CombatHandoff.pending_ground_drops carries combat-loot overflow across the
# combat->overworld scene change (2026-07-14-ground-item-pickups-design.md §3.4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_ground_drops.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var handoff: Node = get_root().get_node("CombatHandoff")
	handoff.clear_pending()

	_check(handoff.pending_ground_drops.is_empty(), "pending_ground_drops starts empty")

	var g: Gear = Gear.new()
	g.display_name = "Test Overflow Item"
	handoff.pending_ground_drops = [g] as Array[Resource]
	_check(handoff.pending_ground_drops.size() == 1, "pending_ground_drops accepts an assigned array")
	_check(handoff.pending_ground_drops[0] == g, "the assigned item is readable back")

	handoff.clear_ground_drops()
	_check(handoff.pending_ground_drops.is_empty(), "clear_ground_drops() empties the field")

	# clear_pending() composes clear_ground_drops() alongside its other three narrower clears.
	handoff.pending_ground_drops = [g] as Array[Resource]
	handoff.clear_pending()
	_check(handoff.pending_ground_drops.is_empty(), "clear_pending() also clears pending_ground_drops")

	print(("COMBAT HANDOFF GROUND DROPS TEST PASSED" if _failures == 0 else "COMBAT HANDOFF GROUND DROPS TEST FAILED: %d" % _failures))
	quit(_failures)
