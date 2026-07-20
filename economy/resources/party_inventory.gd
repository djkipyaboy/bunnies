class_name PartyInventory
extends Resource

## One shared inventory per PC (not per-companion) — spec 2026-07-10 §4.1. Weightless; the Bag
## (Gear + Weapons + Consumables together, 2026-07-14 ground-item-pickups design §2/§3.1) is
## slot-capped (a soft friction lever toward banking/selling/discarding, not a hard wall).
## Materials/Reel-Mods/Quest stay uncapped. `unlocked_companion_slots` increments PERMANENTLY at
## story beats regardless of whether a companion currently occupies the slot.

const BASE_BAG_CAPACITY: int = 20
const BAG_CAPACITY_PER_SLOT: int = 10

@export var gear: Array[Gear] = []
@export var weapons: Array[Weapon] = []   # mirrors `gear`; uncapped like gear (only the Bag TAB's slot count is capped)
@export var reel_mods: Array[Resource] = []    # uncapped; shape TBD when 27-crafting is designed
@export var materials: Array[Resource] = []    # uncapped, stacking
@export var quest_items: Array[Resource] = []  # uncapped; never banked (per-playthrough only)
@export var items: Array[ConsumableItem] = []  # uncapped array, but stacks count toward bag capacity
@export var amber: int = 0   # 2026-07-17 general store design: the world's actual currency
@export var unlocked_companion_slots: int = 0  # 0-2, story-gated
@export var accepted_quest_ids: Array[StringName] = []
@export var completed_quest_ids: Array[StringName] = []

func bag_capacity() -> int:
	return BASE_BAG_CAPACITY + BAG_CAPACITY_PER_SLOT * unlocked_companion_slots

## Gear + Weapons + Consumables share one pool (2026-07-14 ground-item-pickups design §2/§3.1);
## Materials/Quest Items stay uncapped. A Consumable STACK counts as 1 slot, not per-unit — `items`
## already holds one entry per item_type (give_item()/try_give_item() merge into it), so items.size()
## is already "number of distinct stacks."
func bag_count() -> int:
	return gear.size() + weapons.size() + items.size()

func can_add_to_bag() -> bool:
	return bag_count() < bag_capacity()

## "Try" variants are for granting a NEW item from OUTSIDE the bag (loot, ground pickups) — they can
## fail. The existing unconditional give_gear()/give_weapon()/give_item() below stay as-is for
## internal moves that must never fail (equip/unequip swaps, Vault transfers, demo seeding) since
## those never grow bag_count() net (a take always precedes the give).
func try_give_gear(g: Gear) -> bool:
	if not can_add_to_bag():
		return false
	gear.append(g)
	return true

func try_give_weapon(w: Weapon) -> bool:
	if not can_add_to_bag():
		return false
	weapons.append(w)
	return true

## Merging into an existing stack never grows bag_count(), so it always succeeds regardless of
## capacity — only a genuinely new stack entry is capacity-gated.
func try_give_item(item: ConsumableItem) -> bool:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type:
			existing.quantity += item.quantity
			return true
	if not can_add_to_bag():
		return false
	items.append(item)
	return true

## Bag-side add/remove — no capacity check (equip/unequip never touches bag capacity).
func take_gear(g: Gear) -> void:
	gear.erase(g)

func give_gear(g: Gear) -> void:
	gear.append(g)

func take_weapon(w: Weapon) -> void:
	weapons.erase(w)

func give_weapon(w: Weapon) -> void:
	weapons.append(w)

## Adds a gathered/salvaged CraftingMaterial, stacking onto an existing entry of the same
## material_type rather than growing the array unbounded (design-bible 27-crafting.md §11 "stacking").
func give_material(m: CraftingMaterial) -> void:
	for existing: CraftingMaterial in materials:
		if existing is CraftingMaterial and existing.material_type == m.material_type:
			existing.quantity += m.quantity
			return
	materials.append(m)

## Stacks onto an existing entry of the same item_type, mirrors give_material(). items is already
## typed Array[ConsumableItem], so (unlike give_material's materials: Array[Resource]) no runtime
## `is` check is needed.
func give_item(item: ConsumableItem) -> void:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type:
			existing.quantity += item.quantity
			return
	items.append(item)

## Returns the entry for item_type, or null if the party doesn't own one.
func find_item(item_type: StringName) -> ConsumableItem:
	for item: ConsumableItem in items:
		if item.item_type == item_type:
			return item
	return null

## Decrements the matching entry's quantity by 1; removes the entry entirely once it hits 0. No-op
## if the party doesn't own one (defensive — should never be called that way).
func consume_item(item_type: StringName) -> void:
	for i in range(items.size()):
		if items[i].item_type == item_type:
			items[i].quantity -= 1
			if items[i].quantity <= 0:
				items.remove_at(i)
			return

func give_quest_item(q: QuestItem) -> void:
	quest_items.append(q)

func has_quest_item(item_id: StringName) -> bool:
	for q: Resource in quest_items:
		if q is QuestItem and q.item_id == item_id:
			return true
	return false

## Removes the FIRST matching entry. No-op (returns false) if the party doesn't own one.
func consume_quest_item(item_id: StringName) -> bool:
	for i in range(quest_items.size()):
		var q: Resource = quest_items[i]
		if q is QuestItem and q.item_id == item_id:
			quest_items.remove_at(i)
			return true
	return false

func accept_quest(quest_id: StringName) -> void:
	if not accepted_quest_ids.has(quest_id):
		accepted_quest_ids.append(quest_id)

func has_accepted_quest(quest_id: StringName) -> bool:
	return accepted_quest_ids.has(quest_id)

func complete_quest(quest_id: StringName) -> void:
	if not completed_quest_ids.has(quest_id):
		completed_quest_ids.append(quest_id)

func has_completed_quest(quest_id: StringName) -> bool:
	return completed_quest_ids.has(quest_id)
