extends SceneTree

## Real-scene regression for the Treasure Trove's dungeon_demo.gd wiring
## (2026-07-27-treasure-trove-and-mountain-entrance-design.md §3.3). Mirrors
## tests/test_dungeon_lock_and_key.gd's locked/unlocked technique and
## tests/test_dungeon_floor_survives_combat.gd's two-fresh-instance no-respawn technique.
##
## Deviations from the plan's literal test text, both confirmed against real behavior rather than
## guessed: (1) InventoryDemoSetup.seed_demo_party() seeds 30 starting Amber (2026-07-17 general
## store design), so a locked interact() must be checked against "unchanged from its starting
## value," not a literal 0, and an opened trove's +150 Amber lands at 180, not 150. (2)
## queue_free() is deferred — checking get_node_or_null() for the freed trove needs one extra
## processed frame after interact(), matching tests/test_ground_item_pickup.gd's established
## "await process_frame before checking is_instance_valid()" convention.

var _combat_handoff: Node
var _dungeon_instance: Node
var _dungeon_instance_2: Node
var _amber_before: int = -1
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
		var trove: TreasureTrove = dungeon._floors[3].get_node("HollowWardenTrove")
		_check(trove != null, "the Treasure Trove is placed on floor 4")
		_check(trove.boss_defeated == false, "the trove is locked before the boss is defeated")

		_amber_before = dungeon._party_inventory.amber
		trove.interact()
		_check(dungeon._party_inventory.amber == _amber_before, "interacting while locked grants nothing")

		_combat_handoff.mark_defeated(&"DungeonFloor4Enemy")

	if _frames == 2:
		_dungeon_instance.free()

	if _frames == 3:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance_2 = scene.instantiate()
		root.add_child(_dungeon_instance_2)

	if _frames == 4:
		var dungeon_2: DungeonDemo = _dungeon_instance_2
		var trove_2: TreasureTrove = dungeon_2._floors[3].get_node("HollowWardenTrove")
		_check(trove_2.boss_defeated == true, "a fresh scene rebuild sees the trove unlocked once the boss is marked defeated")

		var amber_before_open: int = dungeon_2._party_inventory.amber
		trove_2.interact()
		_check(dungeon_2._party_inventory.amber == amber_before_open + 150, "opening the unlocked trove grants the Amber chunk")
		_check(dungeon_2._party_inventory.has_quest_item(&"sunken_sigil"), "opening the trove grants the Sunken Sigil")

	if _frames == 5:
		# queue_free() is deferred — give it one processed frame to actually take effect.
		var dungeon_2: DungeonDemo = _dungeon_instance_2
		_check(dungeon_2._floors[3].get_node_or_null("HollowWardenTrove") == null, "the trove frees itself once opened")

	if _frames == 6:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		var dungeon_instance_3: Node = scene.instantiate()
		root.add_child(dungeon_instance_3)
		var dungeon_3: DungeonDemo = dungeon_instance_3
		_check(dungeon_3._floors[3].get_node_or_null("HollowWardenTrove") == null, "an already-opened trove does not reappear on a later scene rebuild")
		dungeon_instance_3.free()
		_dungeon_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 8:
		print("ok dungeon-treasure-trove regression complete")
		quit()
		return true
	return false
