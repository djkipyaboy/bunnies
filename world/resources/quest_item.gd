class_name QuestItem
extends Resource

## A key/quest-relevant item that lives in PartyInventory.quest_items (existing since 2026-07-10,
## never populated until now) — uncapped, never banked, visible in the Quest Items tab. First user:
## the dungeon's Rusty Key (2026-07-18 lock-and-key design). item_id is the stable lookup key
## (has_quest_item()/consume_quest_item()); display_name is what the player sees.

@export var display_name: String = ""
@export var item_id: StringName = &""

## Most quest items (keys, etc.) are progression-critical and stay locked to the Quest Items tab —
## this defaults false so every existing quest item is unaffected. A flavor/keepsake item (e.g. the
## Thank You Note, 2026-07-23 playtest feedback) can opt in to being Discard-able like a normal Bag
## item.
@export var discardable: bool = false

## Sale value for a future selling economy (0 = not sellable yet — no such system exists). Kept at 0
## for every quest item until that system is designed.
@export var sale_value: int = 0

## Optional custom confirm-prompt text shown instead of the generic "Discard this item?" — lets a
## sentimental item (the Thank You Note) push back a little before the player tosses it.
@export var discard_flavor_text: String = ""

## Hover-tooltip text shown for this item's row in InventoryMenuPanel's Quest Items tab. Default
## empty — every existing quest item (Rusty Key, Rescued Cat, Thank You Note) shows no tooltip,
## same as before this field existed. First real user: the Treasure Trove's Sunken Sigil, whose
## story significance isn't designed yet — this field carries that stub text.
@export var description: String = ""
