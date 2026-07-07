class_name Interactable
extends Area2D

## Base interaction hook for the demo town (spec §4). Stationary interactables (Door,
## AdventuringBoard) extend this directly and override interact(). Moving interactables
## (Villager) instead ADD a plain Interactable as a child node and connect to its
## `interacted` signal, since a CharacterBody2D can't also be an Area2D.
##
## Sets its own collision shape/layer in _ready() so every subclass and every composed
## child gets working overlap detection for free (layer 2 — see PCController's
## InteractionReach, which monitors that layer).

## Shown in the InteractPrompt UI whenever the PC's interaction reach overlaps this node.
@export var prompt_text: String = "Interact"

## Radius of the default collision circle created in _ready().
@export var interaction_radius: float = 16.0

## Emitted by the default interact() implementation. Subclasses that override interact()
## may skip emitting this if they don't need external listeners.
signal interacted

func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interaction_radius
	shape.shape = circle
	add_child(shape)

func interact() -> void:
	interacted.emit()

## Returns whichever candidate is closest to from_position, or null if candidates is
## empty. Pure/static so it's unit-testable without a live physics query.
static func nearest(candidates: Array[Interactable], from_position: Vector2) -> Interactable:
	var best: Interactable = null
	var best_dist: float = INF
	for candidate: Interactable in candidates:
		var dist: float = candidate.global_position.distance_squared_to(from_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best
