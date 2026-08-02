class_name GatheringNode
extends Interactable

## A stationary, contact-triggered environmental gathering node for the overworld map -- Foraging
## profession (design-bible 27-crafting.md section 11; 2026-08-01 gathering-profession-minigames
## spec section 2). HANDS OFF to the driving scene's ForagingPanel on interact() -- mirrors
## RandomEncounterNode's shape (a stationary Interactable that hands data to whoever's listening; the
## driving scene opens the actual panel), not RewardPickup's self-contained-resolution shape, since a
## Shake/Bank choice needs the scene's existing panel/movement-pause plumbing.
##
## Marks itself defeated + frees on interact() -- the gathering attempt has started regardless of how
## many times the player shakes or when they bank, so the world node itself doesn't linger through
## the mini-game (same rationale as RandomEncounterNode's own doc-comment).

@export var material_type: StringName = &""
@export var material_display_name: String = ""
@export var quantity: int = 1

## Emitted right before this node frees itself; the driving scene opens its ForagingPanel with this
## payload (replaces the old material_gathered signal -- granting now happens on the panel's Bank
## button, not here, so this signal names what's being REQUESTED, not what was granted).
signal foraging_requested(material_type: StringName, material_display_name: String, quantity: int)

func _init() -> void:
	auto_trigger = true
	prompt_text = "Gather"

	var visual := ColorRect.new()
	visual.color = Color(0.3, 0.7, 0.3)
	visual.position = Vector2(-8, -8)
	visual.size = Vector2(16, 16)
	add_child(visual)

func interact() -> void:
	_handoff().mark_defeated(StringName(name))
	foraging_requested.emit(material_type, material_display_name, quantity)
	queue_free()

## Fetches the CombatHandoff autoload by path -- same rationale as RewardPickup/OverworldEnemy's
## _handoff() (bare identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
