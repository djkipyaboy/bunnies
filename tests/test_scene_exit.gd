extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var exit := SceneExit.new()
	_check(exit.target_scene_path == "", "target_scene_path defaults to empty")
	exit.target_scene_path = "res://world/town_demo.tscn"
	_check(exit.target_scene_path == "res://world/town_demo.tscn", "target_scene_path is settable")
	_check(exit.prompt_text == "Interact", "prompt_text keeps Interactable's default (SceneExit doesn't hardcode one)")
	_check(exit.fade_overlay == null, "fade_overlay defaults to unset")
	exit.free()  # an Area2D (Node, not RefCounted) never added to a tree — free explicitly
	quit()
