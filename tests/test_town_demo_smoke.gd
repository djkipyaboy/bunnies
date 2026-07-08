extends SceneTree

## Headless smoke test for the demo town scene (2026-07-07-demo-town-prototype-design.md).
## Confirms the scene loads and runs a few frames without a script/runtime error.
## This does NOT verify movement feel, dialogue flow, door transitions, or any other
## subjective playtest criterion from the plan's Task 11 checklist — that verification
## requires a human actually running the scene and is explicitly out of scope here.

var _instance: Node
var _frames: int = 0

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 5:
		print("ok town_demo.tscn loaded and ran 5 process frames without crashing")
		_instance.free()
		return true
	return false
