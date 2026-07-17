class_name ShopStockEntry
extends Resource

## One purchasable line in a vendor's catalog (2026-07-17 general store design). `item` is a Gear,
## Weapon, or ConsumableItem TEMPLATE — buying duplicates it (mirrors LootEntry's own
## duplicate-on-grant convention, so two purchases of the same line never alias the same Resource).
## `stock` decrements per purchase and does NOT replenish this pass (a fixed pool is fine for
## playtesting; a restock timer is future work, not built here).

@export var item: Resource
@export var price: int = 1
@export var stock: int = 3
