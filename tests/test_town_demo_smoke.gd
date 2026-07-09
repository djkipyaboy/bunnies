extends SceneTree

## Headless smoke test for the demo town scene (2026-07-07-demo-town-prototype-design.md).
## Confirms the scene loads and runs a few frames without a script/runtime error, and that the
## PC/actor Y-sort fix (2026-07-08-town-overworld-y-sort-fix-design.md) is wired: Exterior/
## ShopInterior are Y-sort containers and the PC is a real child of the active one at scene start.
## This does NOT verify movement feel, dialogue flow, door transitions, or any other subjective
## playtest criterion from the plan's Task 11 checklist — that verification requires a human
## actually running the scene and is explicitly out of scope here.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		_check(town._exterior.y_sort_enabled, "Exterior has y_sort_enabled")
		_check(town._interior.y_sort_enabled, "ShopInterior has y_sort_enabled")
		_check(town._pc.get_parent() == town._exterior, "PC is a real child of Exterior at scene start")
	if _frames >= 5:
		print("ok town_demo.tscn loaded and ran 5 process frames without crashing")
		_instance.free()
		return true
	return false
