class_name ConsumableItem
extends Resource

## A stacking consumable (Healing Potion is the first — 2026-07-14 combat items menu design §3).
## Mirrors CraftingMaterial's shape/stacking convention exactly: a typed, stacking quantity, no
## rarity/affix data. heal_amount is the only effect field this pass needs (one item type).

@export var display_name: String = ""
@export var item_type: StringName = &""
@export var quantity: int = 1
@export var heal_amount: int = 0
@export var effect_type: StringName = &"heal"
