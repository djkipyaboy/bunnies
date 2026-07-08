class_name OverworldDemo
extends Node2D

## Root scene for the overworld demo prototype (2026-07-08-overworld-demo-prototype-design.md).
## Flat top-down, same style/camera/movement code as town_demo.gd — the design bible's locked
## tilted/dimetric overworld look is a separate, later visual pass (spec §0). Proves: a
## walkable map with real physical obstacles (a river only crossable at one bridge), and a
## landmark that transitions to a DIFFERENT scene (town_demo.tscn) via a fade, unlike the
## town's same-scene, no-fade Door toggle. No content commitment: layout/obstacle positions
## are disposable placeholders.

const OVERWORLD_BOUNDS := Rect2(0, 0, 1280, 720)
const RIVER_X_START: float = 600.0
const RIVER_WIDTH: float = 60.0
const BRIDGE_GAP_Y_START: float = 300.0
const BRIDGE_GAP_HEIGHT: float = 80.0
const MOUNTAIN_RECT := Rect2(1080, 40, 160, 160)
const VILLAGE_POSITION := Vector2(200, 360)
const PC_SPAWN := Vector2(200, 460)

var _world: Node2D
var _pc: PCController
var _camera: Camera2D
var _interact_prompt: InteractPrompt
var _fade_overlay: FadeOverlay
var _highlighted_target: Interactable

func _ready() -> void:
	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)
	_build_world()
	_build_pc()
	_build_camera()
	_build_ui()

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	var ground := ColorRect.new()
	ground.color = Color(0.5, 0.6, 0.4)
	ground.position = OVERWORLD_BOUNDS.position
	ground.size = OVERWORLD_BOUNDS.size
	_world.add_child(ground)

	_build_river()
	_build_mountain()
	_build_trees()
	_build_village()

	WorldGeometry.add_boundary_walls(_world, OVERWORLD_BOUNDS)

func _build_river() -> void:
	var river_visual := ColorRect.new()
	river_visual.color = Color(0.3, 0.5, 0.75)
	river_visual.position = Vector2(RIVER_X_START, OVERWORLD_BOUNDS.position.y)
	river_visual.size = Vector2(RIVER_WIDTH, OVERWORLD_BOUNDS.size.y)
	_world.add_child(river_visual)

	var bridge_gap_end: float = BRIDGE_GAP_Y_START + BRIDGE_GAP_HEIGHT
	var river_north := Rect2(RIVER_X_START, OVERWORLD_BOUNDS.position.y, RIVER_WIDTH, BRIDGE_GAP_Y_START - OVERWORLD_BOUNDS.position.y)
	var river_south := Rect2(RIVER_X_START, bridge_gap_end, RIVER_WIDTH, OVERWORLD_BOUNDS.end.y - bridge_gap_end)
	WorldGeometry.add_solid_collider(_world, river_north)
	WorldGeometry.add_solid_collider(_world, river_south)

	var bridge_deck := ColorRect.new()
	bridge_deck.color = Color(0.55, 0.4, 0.25)
	bridge_deck.position = Vector2(RIVER_X_START - 10.0, BRIDGE_GAP_Y_START)
	bridge_deck.size = Vector2(RIVER_WIDTH + 20.0, BRIDGE_GAP_HEIGHT)
	_world.add_child(bridge_deck)

func _build_mountain() -> void:
	var visual := ColorRect.new()
	visual.color = Color(0.5, 0.5, 0.52)
	visual.position = MOUNTAIN_RECT.position
	visual.size = MOUNTAIN_RECT.size
	_world.add_child(visual)
	WorldGeometry.add_solid_collider(_world, MOUNTAIN_RECT)

func _build_trees() -> void:
	var tree_positions: Array[Vector2] = [
		Vector2(80, 150), Vector2(350, 120), Vector2(450, 550), Vector2(120, 600),
		Vector2(750, 180), Vector2(950, 500), Vector2(1150, 300),
	]
	for tree_position: Vector2 in tree_positions:
		_world.add_child(_build_tree(tree_position))

func _build_tree(tree_position: Vector2) -> Node2D:
	var tree := Node2D.new()
	tree.position = tree_position

	var trunk := ColorRect.new()
	trunk.color = Color(0.4, 0.28, 0.16)
	trunk.position = Vector2(-4, -4)
	trunk.size = Vector2(8, 16)
	tree.add_child(trunk)

	var canopy := ColorRect.new()
	canopy.color = Color(0.25, 0.45, 0.22)
	canopy.position = Vector2(-14, -28)
	canopy.size = Vector2(28, 28)
	tree.add_child(canopy)

	WorldGeometry.add_solid_collider(tree, Rect2(-10, -10, 20, 20))
	return tree

func _build_village() -> void:
	var landmark := Node2D.new()
	landmark.position = VILLAGE_POSITION

	var roof := Polygon2D.new()
	roof.color = Color(0.42, 0.26, 0.18)
	roof.polygon = PackedVector2Array([Vector2(-30, 10), Vector2(0, -30), Vector2(30, 10)])
	landmark.add_child(roof)

	var body := ColorRect.new()
	body.color = Color(0.72, 0.58, 0.38)
	body.position = Vector2(-25, 10)
	body.size = Vector2(50, 30)
	landmark.add_child(body)

	_world.add_child(landmark)
	WorldGeometry.add_solid_collider(_world, Rect2(VILLAGE_POSITION.x - 25.0, VILLAGE_POSITION.y + 10.0, 50.0, 30.0))

	var entrance := SceneExit.new()
	entrance.name = "VillageEntrance"
	entrance.prompt_text = "Enter Village"
	entrance.target_scene_path = "res://world/town_demo.tscn"
	entrance.global_position = VILLAGE_POSITION + Vector2(0, 40)
	entrance.fade_overlay = _fade_overlay
	_world.add_child(entrance)

func _build_pc() -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	_pc.global_position = PC_SPAWN

	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 8.0
	capsule.height = 20.0
	shape.shape = capsule
	_pc.add_child(shape)

	var visual := ColorRect.new()
	visual.color = Color(0.85, 0.55, 0.25)
	visual.position = Vector2(-8, -12)
	visual.size = Vector2(16, 24)
	_pc.add_child(visual)

	add_child(_pc)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	_camera.limit_left = int(OVERWORLD_BOUNDS.position.x)
	_camera.limit_top = int(OVERWORLD_BOUNDS.position.y)
	_camera.limit_right = int(OVERWORLD_BOUNDS.end.x)
	_camera.limit_bottom = int(OVERWORLD_BOUNDS.end.y)
	_pc.add_child(_camera)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	_interact_prompt = InteractPrompt.new()
	_interact_prompt.position = Vector2(16, 16)
	ui.add_child(_interact_prompt)

func _process(_delta: float) -> void:
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		_interact_prompt.show_prompt(target.prompt_text)
	else:
		_interact_prompt.hide_prompt()
	_set_highlighted_target(target)

func _set_highlighted_target(target: Interactable) -> void:
	if target == _highlighted_target:
		return
	if _highlighted_target != null:
		_highlighted_target.set_highlighted(false)
	if target != null:
		target.set_highlighted(true)
	_highlighted_target = target

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		target.interact()
