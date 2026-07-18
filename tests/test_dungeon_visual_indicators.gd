extends SceneTree

## Regression for a human-playtest-found UX gap (2026-07-17): stairs and the dungeon entrance/exit
## sit on flat, featureless ground with zero visual indicator (no ColorRect/shape at all beyond an
## invisible Area2D), so the player couldn't see where to interact. Mirrors the existing
## TownExit/ExitDoor arrow convention (town_demo.gd) — a yellow Polygon2D wired as highlight_visual,
## dim by default, brightened by Interactable.set_highlighted() when the PC is in range.

var _dungeon_instance: Node
var _overworld_instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var dungeon_scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_dungeon_instance = dungeon_scene.instantiate()
	root.add_child(_dungeon_instance)

	var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
	_overworld_instance = overworld_scene.instantiate()
	root.add_child(_overworld_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var dungeon: DungeonDemo = _dungeon_instance
		var stairs_down: Stairs = dungeon._floors[0].get_node("StairsDown")
		var stairs_up: Stairs = dungeon._floors[1].get_node("StairsUp")
		_check(stairs_down.highlight_visual != null, "floor 1's StairsDown has a visible highlight_visual marker")
		_check(stairs_up.highlight_visual != null, "floor 2's StairsUp has a visible highlight_visual marker")
		_check(dungeon._dungeon_exit.highlight_visual != null, "the DungeonExit has a visible highlight_visual marker")

		var overworld: OverworldDemo = _overworld_instance
		_check(overworld._dungeon_entrance.highlight_visual != null, "the overworld's DungeonEntranceDebug has a visible highlight_visual marker")

		_dungeon_instance.free()
		_overworld_instance.free()
		get_root().get_node("CombatHandoff").clear_pending()

	if _frames >= 2:
		print("ok dungeon-visual-indicators regression complete")
		quit()
		return true
	return false
