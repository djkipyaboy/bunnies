class_name GroundItemPickup
extends Interactable

## A dropped item sitting on the ground — either combat-loot overflow (spawned in the overworld at
## the return position) or a player's manual Discard (spawned at the PC's current position). Holds
## exactly one of Gear, Weapon, ConsumableItem, or CraftingMaterial. Requires a deliberate interact
## keypress to collect (auto_trigger stays false, the Interactable default) — see
## 2026-07-14-ground-item-pickups-design.md §2/§3.2.

## Set externally AFTER .new() and BEFORE add_child() (see the driving scenes' spawn call sites) —
## _ready() reads this, so it must already be assigned by the time this node enters the tree.
@export var item: Resource

## Set externally at placement time (same convention as RewardPickup.party_inventory).
var party_inventory: PartyInventory

const PLACEHOLDER_TINT: Color = Color(0.6, 0.6, 0.6)   # Consumable/CraftingMaterial — no rarity concept

signal item_picked_up(item_name: String)
signal pickup_rejected(item_name: String)   # Bag full — item stays on the ground

var _proximity_label: Label

func _init() -> void:
	prompt_text = "Pick up"

func _ready() -> void:
	super._ready()   # Interactable's own collision-shape setup
	var glow := ColorRect.new()
	glow.color = RarityVisuals.color(item.rarity) if (item is Gear or item is Weapon) else PLACEHOLDER_TINT
	glow.position = Vector2(-12, -12)
	glow.size = Vector2(24, 24)
	add_child(glow)

	_proximity_label = Label.new()
	_proximity_label.text = "[E] Pick up %s" % _display_name()
	_proximity_label.position = Vector2(-40, -32)   # floats above the pickup
	_proximity_label.hide()
	add_child(_proximity_label)

func interact() -> void:
	if _try_grant():
		item_picked_up.emit(_display_name())
		queue_free()
	else:
		pickup_rejected.emit(_display_name())

## Overrides the base's alpha-dim behavior (meant for a highlight_visual arrow) with a genuine
## show/hide, since the label must fully disappear out of range, not just dim. Reuses the EXISTING
## per-frame set_highlighted() call every driving scene's nearest-interactable poll already makes —
## no new polling code needed in town_demo.gd/overworld_demo.gd.
func set_highlighted(active: bool) -> void:
	_proximity_label.visible = active

func _try_grant() -> bool:
	if item is Gear:
		return party_inventory.try_give_gear(item as Gear)
	if item is Weapon:
		return party_inventory.try_give_weapon(item as Weapon)
	if item is ConsumableItem:
		return party_inventory.try_give_item(item as ConsumableItem)
	if item is CraftingMaterial:
		party_inventory.give_material(item as CraftingMaterial)   # materials are uncapped
		return true
	if item is QuestItem:
		party_inventory.give_quest_item(item as QuestItem)   # quest items are uncapped
		return true
	return false

func _display_name() -> String:
	if (item is ConsumableItem or item is CraftingMaterial) and item.quantity > 1:
		return "%s x%d" % [item.display_name, item.quantity]
	return item.display_name
