extends SceneTree

## Headless smoke test for the full dungeon_demo.tscn scene (2026-07-17-dungeon-scene-structure-
## design.md) — a fresh launch (no CombatHandoff pending) starts on floor 1, seeds a fresh demo
## party, places one placeholder OverworldEnemy per floor 1-3 (floor 4 reserved for the boss, a
## later step), and wires the floor-1 DungeonExit to the live party.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var dungeon: DungeonDemo = _instance
		var combat_handoff: Node = get_root().get_node("CombatHandoff")

		_check(dungeon._current_floor == 0, "a fresh launch starts on floor 1 (index 0)")
		_check(dungeon._pc.get_parent() == dungeon._floors[0], "the PC is parented into floor 1 on a fresh launch")
		_check(dungeon._pc_combatant != null, "a fresh launch seeds a demo party (no CombatHandoff.pc pending)")

		var enemy_1: OverworldEnemy = dungeon._floors[0].get_node("DungeonFloor1Enemy")
		var enemy_2: OverworldEnemy = dungeon._floors[1].get_node("DungeonFloor2Enemy")
		var enemy_3: OverworldEnemy = dungeon._floors[2].get_node("DungeonFloor3Enemy")
		_check(enemy_1 != null and enemy_1.enemy_ids == [&"rat"], "floor 1 has the rat placeholder encounter")
		_check(enemy_2 != null and enemy_2.enemy_ids == [&"ferret"], "floor 2 has the ferret placeholder encounter")
		_check(enemy_3 != null and enemy_3.enemy_ids == [&"stoat"], "floor 3 has the stoat placeholder encounter")
		_check(dungeon._floors[3].get_node_or_null("DungeonFloor4Enemy") == null, "floor 4 has no placeholder encounter (reserved for the boss, a later step)")
		_check(enemy_1.dungeon_floor == 0, "floor 1's enemy carries dungeon_floor == 0")
		_check(enemy_3.dungeon_floor == 2, "floor 3's enemy carries dungeon_floor == 2")
		_check(enemy_3.pc_node == dungeon._pc, "floor 3's enemy is wired to the dungeon's real PC node")

		_check(dungeon._dungeon_exit != null, "floor 1 has a DungeonExit")
		_check(dungeon._dungeon_exit.pc_combatant == dungeon._pc_combatant, "DungeonExit is wired to the live PC")
		_check(dungeon._dungeon_exit.party_inventory == dungeon._party_inventory, "DungeonExit is wired to the live PartyInventory")

		_instance.free()
		combat_handoff.clear_pending()
	if _frames >= 2:
		quit()
		return true
	return false
