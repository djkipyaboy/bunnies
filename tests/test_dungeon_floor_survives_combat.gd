extends SceneTree

## Regression proving CombatHandoff.dungeon_floor (2026-07-17 dungeon-scene-structure design) does
## its job end to end: a combat round-trip triggered on floor 3 returns the player to floor 3 (not
## floor 1) on rebuild, the defeated floor-3 enemy doesn't reappear, and floor 1/2's enemies are
## untouched. Mirrors tests/test_bench_survives_combat.gd's real end-to-end technique exactly.
##
## Floor changes are driven via DungeonDemo._apply_floor_change() directly (the synchronous half
## Stairs.interact()/travel_to_floor() delegates to) rather than a real Stairs.interact() call —
## travel_to_floor() awaits a real FadeOverlay tween (~18-23 frames at FADE_DURATION=0.3s), which
## this test doesn't need to drive to prove the CombatHandoff round-trip, matching how
## tests/test_overworld_enemy.gd/tests/test_bench_survives_combat.gd call _begin_handoff()/
## _stash_party() directly instead of awaiting a real fade.

var _combat_handoff: Node
var _dungeon_instance: Node
var _dungeon_instance_2: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_dungeon_instance = scene.instantiate()
	root.add_child(_dungeon_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		var dungeon: DungeonDemo = _dungeon_instance
		_check(dungeon._current_floor == 0, "a fresh dungeon launch starts on floor 1 (index 0)")

		var stairs_down_1: Stairs = dungeon._floors[0].get_node("StairsDown")
		dungeon._apply_floor_change(stairs_down_1.target_floor_index, stairs_down_1.target_local_entry)
		var stairs_down_2: Stairs = dungeon._floors[1].get_node("StairsDown")
		dungeon._apply_floor_change(stairs_down_2.target_floor_index, stairs_down_2.target_local_entry)
		_check(dungeon._current_floor == 2, "two floor-change steps land on floor 3 (index 2)")

		var enemy_node: OverworldEnemy = dungeon._floors[2].get_node("DungeonFloor3Enemy")
		enemy_node._begin_handoff()
		_check(_combat_handoff.dungeon_floor == 2, "triggering the floor-3 encounter carries dungeon_floor == 2 into CombatHandoff")
		_check(_combat_handoff.has_return_position == true, "triggering the encounter sets has_return_position")

		_combat_handoff.mark_defeated(_combat_handoff.pending_encounter_id)
		_combat_handoff.clear_combat_data()

	if _frames == 2:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance_2 = scene.instantiate()
		root.add_child(_dungeon_instance_2)

		var dungeon_2: DungeonDemo = _dungeon_instance_2
		_check(dungeon_2._current_floor == 2, "returning from combat rebuilds the dungeon on floor 3 (index 2), not floor 1")
		_check(dungeon_2._floors[2].get_node_or_null("DungeonFloor3Enemy") == null, "the defeated floor-3 enemy does not reappear")
		_check(dungeon_2._floors[0].get_node_or_null("DungeonFloor1Enemy") != null, "floor 1's enemy is untouched")
		_check(dungeon_2._floors[1].get_node_or_null("DungeonFloor2Enemy") != null, "floor 2's enemy is untouched")

		_dungeon_instance.free()
		_dungeon_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 4:
		print("ok dungeon-floor-survives-combat regression complete")
		quit()
		return true
	return false
