extends SceneTree

## Headless smoke test for the full dungeon_demo.tscn scene (2026-07-17-dungeon-scene-structure-
## design.md, encounter composition escalated 2026-07-18) — a fresh launch (no CombatHandoff pending)
## starts on floor 1, seeds a fresh demo party, places one escalating OverworldEnemy encounter per
## floor 1-3 (floor 4 reserved for the boss, a later step), and wires the floor-1 DungeonExit to the
## live party.

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
		_check(enemy_1 != null and enemy_1.enemy_ids == [&"rat"], "floor 1 has a single-enemy encounter (rat)")
		_check(enemy_2 != null and enemy_2.enemy_ids == [&"rat", &"ferret"], "floor 2 has a 2-enemy encounter (rat + ferret)")
		_check(enemy_3 != null and enemy_3.enemy_ids == [&"rat", &"ferret", &"stoat"], "floor 3 has a 3-enemy encounter (rat + ferret + stoat)")
		var enemy_4: OverworldEnemy = dungeon._floors[3].get_node("DungeonFloor4Enemy")
		_check(enemy_4 != null and enemy_4.enemy_ids == [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"], "floor 4 has the Hollow Warden encounter (boss + 2 lesser acolytes)")
		_check(enemy_4.dungeon_floor == 3, "floor 4's enemy carries dungeon_floor == 3")
		_check(enemy_1.dungeon_floor == 0, "floor 1's enemy carries dungeon_floor == 0")
		_check(enemy_3.dungeon_floor == 2, "floor 3's enemy carries dungeon_floor == 2")
		_check(enemy_3.pc_node == dungeon._pc, "floor 3's enemy is wired to the dungeon's real PC node")

		_check(dungeon._dungeon_exit != null, "floor 1 has a DungeonExit")
		_check(dungeon._dungeon_exit.pc_combatant == dungeon._pc_combatant, "DungeonExit is wired to the live PC")
		_check(dungeon._dungeon_exit.party_inventory == dungeon._party_inventory, "DungeonExit is wired to the live PartyInventory")

		var cat: CagedCat = dungeon._floors[3].get_node("WhiskersPickup")
		_check(cat != null, "floor 4 has a node named WhiskersPickup")
		_check(cat is CagedCat, "WhiskersPickup is a CagedCat")
		_check(cat.boss_defeated == combat_handoff.is_defeated(&"DungeonFloor4Enemy"), "the cat's boss_defeated matches the Hollow Warden's defeated state at build time")
		_check(cat.boss_defeated == false, "on a fresh, undefeated-boss scenario, the cat starts locked")
		_check(cat.party_inventory == dungeon._party_inventory, "the cat is wired to the scene's live PartyInventory")

		_instance.free()
		combat_handoff.clear_pending()
	if _frames >= 2:
		quit()
		return true
	return false
