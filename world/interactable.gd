class_name Interactable
extends Area2D

## Base interaction hook for the demo town (spec §4). Stationary interactables (Door,
## AdventuringBoard, SceneExit) extend this directly and override interact(). Moving
## interactables (Villager) instead ADD a plain Interactable as a child node and connect to
## its `interacted` signal, since a CharacterBody2D can't also be an Area2D.
##
## Sets its own collision shape/layer in _ready() so every subclass and every composed
## child gets working overlap detection for free (layer 2 — see PCController's
## InteractionReach, which monitors that layer).

## Shown in the InteractPrompt UI whenever the PC's interaction reach overlaps this node.
@export var prompt_text: String = "Interact"

## Radius of the default collision circle created in _ready().
@export var interaction_radius: float = 16.0

## Optional highlight visual (e.g. an exit arrow) — dims by default, brightens when the PC
## is in interact range. Left null for interactables with no such visual. Moved up from Door
## (2026-07-08-overworld-demo-prototype-design.md §5) so SceneExit gets the same behavior for
## free instead of re-declaring it.
@export var highlight_visual: CanvasItem

## When true, the driving scene calls interact() the instant this becomes the nearest
## interactable in range — no keypress required. Default false, so every existing
## interactable (Door, SceneExit, AdventuringBoard, Villager's Talk zone) is completely
## unaffected. Read by whichever scene's _process() polls nearest_interactable() each
## frame (see docs/superpowers/specs/2026-07-11-overworld-npc-encounters-design.md §3.1).
@export var auto_trigger: bool = false

const DIM_ALPHA: float = 0.2

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

## Called by callers that track "nearest interactable" (town_demo.gd's/overworld_demo.gd's
## _process) so the world can visually indicate what's currently in interact range. No-op if
## no highlight_visual is assigned.
func set_highlighted(active: bool) -> void:
	if not is_instance_valid(highlight_visual):
		return
	highlight_visual.modulate.a = 1.0 if active else DIM_ALPHA

## Returns whichever candidate is closest to from_position, or null if candidates is
## empty. Pure/static so it's unit-testable without a live physics query. Skips any candidate
## that's been queue_free()'d (auto_trigger interactables like OverworldEnemy/RewardPickup free
## themselves mid-scene; area_exited removes them from the tracker, but that's a deferred signal,
## so a freed-yet-still-tracked reference can exist for part of a frame).
static func nearest(candidates: Array[Interactable], from_position: Vector2) -> Interactable:
	var best: Interactable = null
	var best_dist: float = INF
	for candidate: Interactable in candidates:
		if not is_instance_valid(candidate):
			continue
		var dist: float = candidate.global_position.distance_squared_to(from_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best
