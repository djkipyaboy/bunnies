class_name FishingSpot
extends Interactable

## A stationary, contact-triggered overworld fishing node (2026-08-01
## gathering-profession-minigames spec section 3) -- a claw-machine-style catch, distinct from
## GatheringNode's touch-and-grant flow. HANDS OFF to the driving scene's FishingPanel on
## interact() (mirrors GatheringNode/RandomEncounterNode's shape) -- marks itself defeated and
## frees itself, since the catch attempt has started regardless of what the player does in the
## panel afterward. Carries one material/quantity config PER shadow-size bucket (small/medium/
## large) since real fish content doesn't exist yet -- placeholder authoring fields, not a catalog.

@export var small_material_type: StringName = &""
@export var small_material_display_name: String = ""
@export var small_quantity: int = 1

@export var medium_material_type: StringName = &""
@export var medium_material_display_name: String = ""
@export var medium_quantity: int = 1

@export var large_material_type: StringName = &""
@export var large_material_display_name: String = ""
@export var large_quantity: int = 1

## Emitted right before this node frees itself; the driving scene opens its FishingPanel with this
## payload. Keyed by size bucket, each value {"material_type", "material_display_name", "quantity"}.
signal fishing_requested(bucket_configs: Dictionary)

func _init() -> void:
	auto_trigger = true
	prompt_text = "Fish"

	var visual := ColorRect.new()
	visual.color = Color(0.2, 0.4, 0.8)
	visual.position = Vector2(-8, -8)
	visual.size = Vector2(16, 16)
	add_child(visual)

func interact() -> void:
	_handoff().mark_defeated(StringName(name))
	fishing_requested.emit(_build_bucket_configs())
	queue_free()

func _build_bucket_configs() -> Dictionary:
	return {
		&"small": {"material_type": small_material_type, "material_display_name": small_material_display_name, "quantity": small_quantity},
		&"medium": {"material_type": medium_material_type, "material_display_name": medium_material_display_name, "quantity": medium_quantity},
		&"large": {"material_type": large_material_type, "material_display_name": large_material_display_name, "quantity": large_quantity},
	}

## Fetches the CombatHandoff autoload by path -- same rationale as every other _handoff() in this
## project (bare identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
