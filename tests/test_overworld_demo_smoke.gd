extends SceneTree

## Headless smoke test for the overworld demo scene (2026-07-08-overworld-demo-prototype-design.md).
## Confirms the scene loads and runs a few frames without a script/runtime error, and that the
## PC/actor Y-sort fix (2026-07-08-town-overworld-y-sort-fix-design.md) is wired: World is a
## Y-sort container and the PC is a real child of it at scene start. Does NOT verify map feel,
## obstacle placement, the bridge crossing, or the village transition — that verification
## requires a human actually running the scene.

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
		_check(overworld._world.y_sort_enabled, "World has y_sort_enabled")
		_check(overworld._pc.get_parent() == overworld._world, "PC is a real child of World at scene start")
	if _frames >= 5:
		print("ok overworld_demo.tscn loaded and ran 5 process frames without crashing")
		_instance.free()
		return true
	return false
