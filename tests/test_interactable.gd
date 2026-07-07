extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var a := Interactable.new()
	a.position = Vector2(0, 0)
	var b := Interactable.new()
	b.position = Vector2(100, 0)
	var c := Interactable.new()
	c.position = Vector2(10, 0)

	var candidates: Array[Interactable] = [a, b, c]
	var nearest_to_origin: Interactable = Interactable.nearest(candidates, Vector2(0, 0))
	_check(nearest_to_origin == a, "nearest() picks the closest candidate to the query point")

	var nearest_to_far_point: Interactable = Interactable.nearest(candidates, Vector2(95, 0))
	_check(nearest_to_far_point == b, "nearest() re-picks correctly for a different query point")

	var empty_candidates: Array[Interactable] = []
	_check(Interactable.nearest(empty_candidates, Vector2.ZERO) == null, "nearest() returns null for an empty list")

	# GDScript lambdas capture outer locals BY VALUE — a plain `var fired: bool` reassigned
	# inside the lambda would never propagate out. Route it through a one-element array.
	var fired: Array[bool] = [false]
	a.interacted.connect(func() -> void: fired[0] = true)
	a.interact()
	_check(fired[0], "default interact() emits the interacted signal")

	_check(a.prompt_text == "Interact", "prompt_text defaults to 'Interact'")
	a.prompt_text = "Talk"
	_check(a.prompt_text == "Talk", "prompt_text is settable")

	# a/b/c are Area2D (Node, not RefCounted) and were never added to a tree — free them
	# explicitly or the process reports leaked instances at exit.
	a.free()
	b.free()
	c.free()
	quit()
