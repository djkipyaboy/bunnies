class_name GatheringNode
extends Interactable

## A stationary, contact-triggered environmental gathering node for the overworld map — Foraging/
## Fishing professions (design-bible 27-crafting.md §11). Deliberately minimal for the current
## playtest: touch it, get a flat Material into the Materials tab, it removes itself. No mini-game
## reel, no rarity/quantity roll, no respawn timer — all future work per §11. Mirrors
## world/reward_pickup.gd's shape almost exactly (auto_trigger, defeated-tracking, self-free).

@export var material_type: StringName = &""
@export var material_display_name: String = ""
@export var quantity: int = 1

## Set by whoever instantiates this at placement time (mirrors RewardPickup's party_inventory).
var party_inventory: PartyInventory

## Emitted right before this node frees itself, so the driving scene can show a "you gathered
## this" message (mirrors RewardPickup.item_picked_up).
signal material_gathered(item_name: String, quantity: int)

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
	var m: CraftingMaterial = CraftingMaterial.new()
	m.display_name = material_display_name
	m.material_type = material_type
	m.quantity = quantity
	party_inventory.give_material(m)
	material_gathered.emit(material_display_name, quantity)
	queue_free()

## Fetches the CombatHandoff autoload by path — same rationale as RewardPickup._handoff()/
## OverworldEnemy._handoff() (bare identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
