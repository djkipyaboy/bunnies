extends SceneTree

## Real-scene test for the 3 authored hover tooltips (Old Well, Adventuring Board, Shop door) —
## mirrors tests/test_overworld_demo_gathering_content.gd's real-scene-instance technique. Emits
## mouse_entered/mouse_exited directly (see tests/test_interactable_hover.gd's rationale) rather
## than simulating real mouse motion.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	var demo: TownDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var board: AdventuringBoard = demo.get_node("Exterior/AdventuringBoard")
	_check(board.hover_description == "Town quest board — accept and turn in quests here.", "board has its authored hover text")
	board.mouse_entered.emit()
	await process_frame
	_check(demo._world_tooltip.visible, "hovering the board shows the tooltip")
	_check(demo._world_tooltip.text == board.hover_description, "the tooltip shows the board's hover text")
	board.mouse_exited.emit()
	await process_frame
	_check(not demo._world_tooltip.visible, "leaving the board hides the tooltip")

	var old_well: OldWell = demo.get_node("Exterior/OldWell")
	_check(not old_well.hover_description.is_empty(), "Old Well has authored hover text")
	old_well.mouse_entered.emit()
	await process_frame
	_check(demo._world_tooltip.text == old_well.hover_description, "hovering the Old Well shows its own text")
	old_well.mouse_exited.emit()

	var shop_door: Door = demo.get_node("Exterior/ShopDoor")
	_check(not shop_door.hover_description.is_empty(), "the shop door has authored hover text")
	shop_door.mouse_entered.emit()
	await process_frame
	_check(demo._world_tooltip.text == shop_door.hover_description, "hovering the shop door shows its own text")
	shop_door.mouse_exited.emit()

	# --- New: playtest (2026-08-12) found hover tooltips never actually worked with a real mouse —
	# every assertion above emits mouse_entered/exited directly, which never exercises
	# Viewport.physics_object_picking, the thing a real mouse hover actually depends on and which
	# defaults to FALSE in Godot 4. This is the actual regression guard for that root cause. (A fuller
	# end-to-end simulation via a pushed InputEventMouseMotion was attempted but doesn't reliably
	# reach Area2D picking under --headless, which runs without a display server — not something a
	# test in this environment can currently verify further than the flag itself.)
	_check(demo.get_viewport().physics_object_picking, "town_demo enables physics_object_picking so a real mouse hover can work at all")

	quit()
