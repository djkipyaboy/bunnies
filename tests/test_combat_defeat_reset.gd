extends SceneTree

# Headless test: pressing Continue on a LOSS fully restores/revives every PC, hard-resets Bonus
# Meters to floor, and returns the last-visited-town path instead of the original
# overworld/dungeon return_scene_path (2026-08-13 defeat-handling spec §4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_defeat_reset.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	CombatHandoff.last_town_scene_path = "res://world/town_demo.tscn"

	# A PC that DIED in the losing fight (hp 0), meter above floor, some resources spent.
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.hp = 0
	pc.resource_pool.stamina = 0
	pc.bonus_meter.value = pc.bonus_meter.floor + 5
	var meter_floor: int = pc.bonus_meter.floor

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	# The fight was triggered deep in a dungeon, NOT in town -- the loss must NOT send the player
	# back here.
	var dungeon_return_path: String = "res://world/dungeon_demo.tscn"
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"DungeonFloor3Enemy", dungeon_return_path, Vector2(5.0, 6.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	inst._last_result_won = false
	var returned_path: String = inst.press_continue_for_test()

	_check(pc.hp == pc.max_hp, "LOSS + Continue revives the dead PC to full HP (got %d/%d)" % [pc.hp, pc.max_hp])
	_check(pc.resource_pool.stamina == pc.resource_pool.max_stamina, "LOSS + Continue restores Stamina to max")
	_check(pc.bonus_meter.value == meter_floor, "LOSS + Continue hard-resets the Bonus Meter to floor %d (got %d)" % [meter_floor, pc.bonus_meter.value])
	_check(returned_path == "res://world/town_demo.tscn", "LOSS + Continue returns the last-visited-town path, NOT the dungeon return_scene_path (got %s)" % returned_path)
	_check(CombatHandoff.is_defeated(&"DungeonFloor3Enemy") == false, "LOSS + Continue does NOT mark the encounter defeated (regression, unchanged from before this plan)")

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("COMBAT DEFEAT RESET TEST PASSED" if _failures == 0 else "COMBAT DEFEAT RESET TEST FAILED: %d" % _failures))
	quit(_failures)
