class_name RandomEncounterNode
extends Interactable

## A Slay-the-Spire-style "?" overworld encounter trigger (player direction 2026-07-12). Mirrors
## AdventuringBoard's shape (a stationary Interactable that hands data to whoever's listening —
## the driving scene opens the actual panel) rather than RewardPickup's self-contained-resolution
## shape, since a choice UI needs the scene's existing panel/movement-pause plumbing.
##
## Marks itself defeated + frees on trigger (same respawn-on-reload convention as RewardPickup/
## GatheringNode) — the encounter has now started regardless of which option the player picks, so
## the world node itself doesn't linger through the choice.

@export var encounter_id: StringName = &""

signal encounter_triggered(encounter: RandomEncounter)

func _init() -> void:
	auto_trigger = true
	prompt_text = "Investigate"

	var mark := Label.new()
	mark.text = "?"
	mark.add_theme_font_size_override("font_size", 24)
	mark.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	mark.position = Vector2(-8, -28)
	add_child(mark)

func interact() -> void:
	_handoff().mark_defeated(StringName(name))
	encounter_triggered.emit(EncounterLibrary.make(encounter_id))
	queue_free()

## Fetches the CombatHandoff autoload by path — same rationale as RewardPickup/GatheringNode's
## _handoff() (bare identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
