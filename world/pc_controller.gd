class_name PCController
extends CharacterBody2D

## The player-controlled body: free-continuous movement (spec §2) + interaction-reach
## tracking (spec §4). Movement feel itself is a manual playtest call (CLAUDE.md §5 hard
## ceiling) — only Interactable.nearest() (tested in Task 6) backs the logic here.

@export var move_speed: float = 90.0

var _tracked: Array[Interactable] = []
var _movement_paused: bool = false

func _ready() -> void:
	var reach := Area2D.new()
	reach.name = "InteractionReach"
	reach.monitoring = true
	reach.monitorable = false
	reach.collision_layer = 0
	reach.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	reach.add_child(shape)
	add_child(reach)
	reach.area_entered.connect(_on_reach_area_entered)
	reach.area_exited.connect(_on_reach_area_exited)

func _on_reach_area_entered(area: Area2D) -> void:
	if area is Interactable and not _tracked.has(area):
		_tracked.append(area as Interactable)

func _on_reach_area_exited(area: Area2D) -> void:
	if area is Interactable:
		_tracked.erase(area)

func nearest_interactable() -> Interactable:
	return Interactable.nearest(_tracked, global_position)

## Pure velocity calc so movement-pause logic is unit-testable without a running physics frame or
## Input singleton (mirrors Villager.wander_target's "pure + static" pattern). paused (e.g. while
## InventoryMenuPanel is open) always yields zero velocity regardless of input_vector.
static func movement_velocity(input_vector: Vector2, move_speed: float, paused: bool) -> Vector2:
	if paused:
		return Vector2.ZERO
	return input_vector.normalized() * move_speed

## Pauses/resumes PC movement (e.g. while InventoryMenuPanel is open) — same convention as
## Villager.set_wander_paused.
func set_movement_paused(paused: bool) -> void:
	_movement_paused = paused

## Test hook — headless tests can't drive real Input, so expose the flag directly.
func movement_paused_for_test() -> bool:
	return _movement_paused

func _physics_process(_delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	velocity = movement_velocity(input_vector, move_speed, _movement_paused)
	move_and_slide()
