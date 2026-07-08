class_name Villager
extends CharacterBody2D

## A wandering, talkable NPC (spec §5). Also used, with can_wander = false, as the
## Shopkeeper. Composes a plain Interactable child (rather than extending Interactable
## directly) since this node is already a CharacterBody2D — see world/interactable.gd's
## doc comment for why.

signal dialogue_requested(dialogue_set: DialogueSet)

@export var dialogue: DialogueSet
@export var can_wander: bool = true
@export var wander_leash_radius: float = 48.0
@export var wander_speed: float = 40.0
@export var wander_pause_seconds: float = 1.5

var _home_position: Vector2
var _wander_target: Vector2
var _pause_timer: float = 0.0

## Picks a point within leash_radius of origin, given an explicit angle and distance
## fraction (both supplied by the caller so this stays a pure, deterministic,
## unit-testable function — the caller is responsible for supplying randomness).
static func wander_target(origin: Vector2, leash_radius: float, angle: float, distance_fraction: float) -> Vector2:
	var clamped_fraction: float = clampf(distance_fraction, 0.0, 1.0)
	return origin + Vector2(cos(angle), sin(angle)) * leash_radius * clamped_fraction

func _ready() -> void:
	_home_position = global_position
	_wander_target = global_position

	var body_shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 8.0
	capsule.height = 20.0
	body_shape.shape = capsule
	add_child(body_shape)

	var visual := ColorRect.new()
	visual.color = Color(0.35, 0.5, 0.65)
	visual.position = Vector2(-8, -12)
	visual.size = Vector2(16, 24)
	add_child(visual)

	var interaction_zone := Interactable.new()
	interaction_zone.name = "InteractionZone"
	interaction_zone.prompt_text = "Talk"
	add_child(interaction_zone)
	interaction_zone.interacted.connect(_on_interacted)

func _physics_process(delta: float) -> void:
	if not can_wander:
		return
	if global_position.distance_to(_wander_target) < 2.0:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_wander_target = wander_target(_home_position, wander_leash_radius, randf_range(0.0, TAU), randf())
			_pause_timer = wander_pause_seconds
		return
	var direction: Vector2 = global_position.direction_to(_wander_target)
	velocity = direction * wander_speed
	move_and_slide()

func _on_interacted() -> void:
	dialogue_requested.emit(dialogue)
