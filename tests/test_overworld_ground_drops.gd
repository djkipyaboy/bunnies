extends SceneTree

# Headless test: overworld_demo.gd turns CombatHandoff.pending_ground_drops into real
# GroundItemPickup nodes scattered near the PC, and clears the field afterward
# (2026-07-14-ground-item-pickups-design.md §3.5).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_ground_drops.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var handoff: Node = get_root().get_node("CombatHandoff")
	handoff.clear_pending()

	var drop1: Gear = Gear.new()
	drop1.display_name = "Overflow Sword"
	var drop2: Gear = Gear.new()
	drop2.display_name = "Overflow Shield"
	handoff.pending_ground_drops = [drop1, drop2] as Array[Resource]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var inst: OverworldDemo = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var pickups: Array[GroundItemPickup] = []
	for child in inst._world.get_children():
		if child is GroundItemPickup:
			pickups.append(child)
	_check(pickups.size() == 2, "both overflow drops spawn as GroundItemPickup nodes (got %d)" % pickups.size())

	var names: Array[String] = []
	for p: GroundItemPickup in pickups:
		names.append((p.item as Gear).display_name)
		_check(p.party_inventory == inst._party_inventory, "each spawned pickup is wired to the live PartyInventory")
	_check("Overflow Sword" in names, "Overflow Sword is represented")
	_check("Overflow Shield" in names, "Overflow Shield is represented")
	_check(pickups[0].global_position != pickups[1].global_position, "the two drops are scattered, not stacked at the identical position")

	_check(handoff.pending_ground_drops.is_empty(), "pending_ground_drops is cleared once the overworld scene consumes it")

	inst.queue_free()
	await process_frame
	handoff.clear_pending()

	print(("OVERWORLD GROUND DROPS TEST PASSED" if _failures == 0 else "OVERWORLD GROUND DROPS TEST FAILED: %d" % _failures))
	quit(_failures)
