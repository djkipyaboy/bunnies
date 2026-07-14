class_name PartyInventory
extends Resource

## One shared inventory per PC (not per-companion) — spec 2026-07-10 §4.1. Weightless; only the
## Gear tab is slot-capped (a soft friction lever toward banking/selling, not a hard wall).
## Materials/Reel-Mods/Quest stay uncapped. `unlocked_companion_slots` increments PERMANENTLY at
## story beats regardless of whether a companion currently occupies the slot.

const BASE_GEAR_CAPACITY: int = 20
const GEAR_CAPACITY_PER_SLOT: int = 10

@export var gear: Array[Gear] = []
@export var weapons: Array[Weapon] = []   # mirrors `gear`; uncapped like gear (only the Gear TAB's slot count is capped)
@export var reel_mods: Array[Resource] = []    # uncapped; shape TBD when 27-crafting is designed
@export var materials: Array[Resource] = []    # uncapped, stacking
@export var quest_items: Array[Resource] = []  # uncapped; never banked (per-playthrough only)
@export var items: Array[ConsumableItem] = []  # uncapped, stacking (Healing Potion et al. — 2026-07-14 combat items menu)
@export var gold: int = 0
@export var unlocked_companion_slots: int = 0  # 0-2, story-gated

func gear_capacity() -> int:
	return BASE_GEAR_CAPACITY + GEAR_CAPACITY_PER_SLOT * unlocked_companion_slots

func can_add_gear() -> bool:
	return gear.size() < gear_capacity()

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
