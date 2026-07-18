extends SceneTree

## Regression proving the dungeon's lock-and-key gate (2026-07-18-dungeon-lock-and-key-design.md)
## stays unlocked across a full scene rebuild — the player's own explicit requirement: "the staircase
## remains unlocked permanently after the key has been consumed... go back and forth as often as
## they'd like." Mirrors tests/test_dungeon_floor_survives_combat.gd's real end-to-end technique:
## a second, genuinely fresh dungeon_demo.tscn instance must still see the gate unlocked, even though
## the party no longer holds the (already-consumed) key.
##
## Drives Stairs._try_unlock() + DungeonDemo._apply_floor_change() directly rather than interact()/
## travel_to_floor() — the latter awaits a real ~0.3s FadeOverlay tween this test doesn't need to
## wait out (same reasoning as tests/test_dungeon_lock_and_key.gd).

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
		var key: QuestItem = QuestItem.new()
		key.item_id = &"dungeon_key"
		dungeon._party_inventory.give_quest_item(key)

		var stairs_down_floor3: Stairs = dungeon._floors[2].get_node("StairsDown")
		_check(stairs_down_floor3._try_unlock(), "the key successfully unlocks the gate")
		_check(not dungeon._party_inventory.has_quest_item(&"dungeon_key"), "the key is consumed")
		dungeon._apply_floor_change(stairs_down_floor3.target_floor_index, stairs_down_floor3.target_local_entry)
		_check(dungeon._current_floor == 3, "the unlocked gate travels through to floor 4 (index 3)")

		_dungeon_instance.free()

	if _frames == 2:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance_2 = scene.instantiate()
		root.add_child(_dungeon_instance_2)

		var dungeon_2: DungeonDemo = _dungeon_instance_2
		_check(not dungeon_2._party_inventory.has_quest_item(&"dungeon_key"), "the fresh instance's (freshly-seeded) party does not have the key")

		var stairs_down_floor3_again: Stairs = dungeon_2._floors[2].get_node("StairsDown")
		_check(stairs_down_floor3_again._try_unlock(), "a fresh scene instance, with NO key, still unlocks through the already-unlocked gate")
		dungeon_2._apply_floor_change(stairs_down_floor3_again.target_floor_index, stairs_down_floor3_again.target_local_entry)
		_check(dungeon_2._current_floor == 3, "and actually travels through to floor 4 (index 3)")

		_dungeon_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 4:
		print("ok dungeon-gate-survives-rebuild regression complete")
		quit()
		return true
	return false
