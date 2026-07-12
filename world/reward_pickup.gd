class_name RewardPickup
extends Interactable

## A stationary, contact-triggered reward pickup for the overworld map — walk up to it and it
## grants a placeholder Gear item, then removes itself. Real (not stubbed): appends directly into
## whatever PartyInventory it's wired to at placement time.
## See docs/superpowers/specs/2026-07-11-overworld-npc-encounters-design.md §3.4.

@export var reward_gear: Gear

## Set by whoever instantiates this at placement time (mirrors Door's pc/camera being plain vars
## wired externally rather than looked up).
var party_inventory: PartyInventory

## Emitted right before this pickup frees itself, so the driving scene can show a "you picked
## this up" message (distinct from the encounter-triggered message — player request 2026-07-11).
signal item_picked_up(item_name: String)

func _init() -> void:
	auto_trigger = true
	prompt_text = "Pick up"

	var glow := ColorRect.new()
	glow.color = Color(0.9, 0.75, 0.15)
	glow.position = Vector2(-12, -12)
	glow.size = Vector2(24, 24)
	add_child(glow)

func interact() -> void:
	party_inventory.give_gear(reward_gear)
	item_picked_up.emit(reward_gear.display_name)
	queue_free()
