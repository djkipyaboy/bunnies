extends SceneTree

## Headless test for the dungeon's lock-and-key gate (2026-07-18-dungeon-lock-and-key-design.md),
## updated 2026-07-27 to also cover the key's visibility gate (same-day playtest finding: the key
## was freely grabbable without fighting floor 2's encounter, letting players skip straight from
## floor 1 to the floor-4 boss). The key pickup is now only PLACED once DungeonFloor2Enemy is
## marked defeated — genuinely absent from the scene until then, not just present-but-ungrabbable.
##
## Drives Stairs._try_unlock() (the synchronous lock-check half) directly rather than interact()
## itself — interact() calls the async DungeonDemo.travel_to_floor(), which awaits a real
## FadeOverlay.fade_out() tween (~0.3s / 18-23 frames) that this test doesn't need to wait out to
## prove the lock/unlock/consume logic. Matches this codebase's established "test the synchronous
## half directly" convention (see tests/test_dungeon_demo.gd's _apply_floor_change() checks).

var _dungeon_instance: Node
var _dungeon_instance_2: Node
var _combat_handoff: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("ok " + label)
	else:
		_failures += 1
		print("FAIL " + label)

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
		var stairs_down_floor3: Stairs = dungeon._floors[2].get_node("StairsDown")
		_check(stairs_down_floor3.required_quest_item_id == &"dungeon_key", "floor 3's StairsDown requires the dungeon_key")
		_check(stairs_down_floor3.gate_id != &"", "floor 3's StairsDown has a non-empty gate_id")

		_check(dungeon._floors[1].get_node_or_null("DungeonKeyPickup") == null, "the key is NOT placed before floor 2's encounter is defeated")

		_combat_handoff.mark_defeated(&"DungeonFloor2Enemy")
		_dungeon_instance.free()

	if _frames == 2:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance_2 = scene.instantiate()
		root.add_child(_dungeon_instance_2)

	if _frames == 3:
		var dungeon: DungeonDemo = _dungeon_instance_2

		var key_pickup: GroundItemPickup = dungeon._floors[1].get_node("DungeonKeyPickup")
		_check(key_pickup != null, "the key pickup is placed on floor 2 once its encounter is defeated")
		_check(key_pickup.item is QuestItem and key_pickup.item.item_id == &"dungeon_key", "the key pickup holds a QuestItem with item_id dungeon_key")

		# A fresh dungeon launch starts on floor 1 (index 0) — walk down to floor 3 (index 2) first
		# via _apply_floor_change() directly (mirrors tests/test_dungeon_floor_survives_combat.gd's
		# identical two-step navigation) so the "still on floor 3" checks below are meaningful.
		var stairs_down_1: Stairs = dungeon._floors[0].get_node("StairsDown")
		dungeon._apply_floor_change(stairs_down_1.target_floor_index, stairs_down_1.target_local_entry)
		var stairs_down_2: Stairs = dungeon._floors[1].get_node("StairsDown")
		dungeon._apply_floor_change(stairs_down_2.target_floor_index, stairs_down_2.target_local_entry)
		_check(dungeon._current_floor == 2, "two floor-change steps land on floor 3 (index 2)")

		var stairs_down_floor3: Stairs = dungeon._floors[2].get_node("StairsDown")

		# Try the locked stairs WITHOUT the key.
		_check(not stairs_down_floor3._try_unlock(), "_try_unlock() fails without the key")
		_check(dungeon._current_floor == 2, "still on floor 3 (index 2) — a failed unlock never travels")
		_check(not dungeon.is_gate_unlocked(&"dungeon_floor3_to_4_gate"), "the gate is still locked")
		_check(dungeon._pickup_debug_label.text.contains("locked"), "a failed unlock shows a locked message on screen")

		# Grant the key directly (mirrors picking it up) and unlock.
		var key: QuestItem = QuestItem.new()
		key.item_id = &"dungeon_key"
		key.display_name = "Rusty Key"
		dungeon._party_inventory.give_quest_item(key)
		_check(stairs_down_floor3._try_unlock(), "_try_unlock() succeeds once the party holds the key")
		_check(not dungeon._party_inventory.has_quest_item(&"dungeon_key"), "the key was consumed on successful unlock")
		_check(_combat_handoff.is_gate_unlocked(&"dungeon_floor3_to_4_gate"), "the gate is now permanently marked unlocked")
		_check(dungeon._pickup_debug_label.text.contains("unlock"), "a successful unlock shows an on-screen confirmation message (playtest-found gap, 2026-07-18)")

		# _try_unlock() only decides whether to proceed — apply the actual floor change directly
		# (the same synchronous method travel_to_floor() itself calls after its fade), proving the
		# unlocked path really does reach floor 4.
		dungeon._apply_floor_change(stairs_down_floor3.target_floor_index, stairs_down_floor3.target_local_entry)
		_check(dungeon._current_floor == 3, "applying the floor change after a successful unlock reaches floor 4 (index 3)")

		_dungeon_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 5:
		print(("ok dungeon-lock-and-key regression complete" if _failures == 0 else "FAIL dungeon-lock-and-key regression: %d failure(s)" % _failures))
		quit(_failures)
		return true
	return false
