extends SceneTree

## Smoke test for the overworld->dungeon entrance (2026-07-17-dungeon-scene-structure-design.md §3.6,
## prompt text finalized 2026-07-27) — a SceneExit near the mountain leading into dungeon_demo.tscn.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var overworld: OverworldDemo = _instance
		_check(overworld._dungeon_entrance != null, "overworld builds a DungeonEntranceDebug SceneExit")
		_check(overworld._dungeon_entrance.target_scene_path == "res://world/dungeon_demo.tscn", "DungeonEntranceDebug targets dungeon_demo.tscn")
		_check(overworld._dungeon_entrance.prompt_text == "Enter the Dungeon", "the dungeon entrance's prompt text is finalized, no longer marked temporary")
		_check(overworld._dungeon_entrance.pc_combatant == overworld._pc_combatant, "DungeonEntranceDebug is wired to the overworld's live PC")
		_check(overworld._dungeon_entrance.party_inventory == overworld._party_inventory, "DungeonEntranceDebug is wired to the overworld's live PartyInventory")
		_instance.free()
		get_root().get_node("CombatHandoff").clear_pending()
	if _frames >= 2:
		quit()
		return true
	return false
