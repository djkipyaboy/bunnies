extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var prompt := InteractPrompt.new()
	_check(not prompt.visible, "InteractPrompt starts hidden")
	prompt.show_prompt("Talk")
	_check(prompt.visible, "show_prompt() makes it visible")
	_check(prompt.text == "Talk", "show_prompt() sets the label text")
	prompt.hide_prompt()
	_check(not prompt.visible, "hide_prompt() hides it again")
	prompt.free()  # a Label (Node, not RefCounted) never added to a tree — free explicitly
	quit()
