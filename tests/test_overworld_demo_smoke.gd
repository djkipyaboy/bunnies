extends SceneTree

## Headless smoke test for the overworld demo scene (2026-07-08-overworld-demo-prototype-design.md).
## Confirms the scene loads and runs a few frames without a script/runtime error. Does NOT
## verify map feel, obstacle placement, the bridge crossing, or the village transition — that
## verification requires a human actually running the scene.

var _instance: Node
var _frames: int = 0

func _init() -> void:
	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 5:
		print("ok overworld_demo.tscn loaded and ran 5 process frames without crashing")
		_instance.free()
		return true
	return false
