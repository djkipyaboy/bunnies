class_name Gear
extends Resource

## An equippable item (spec 2026-07-10 §3.1). 5 non-weapon slots — the weapon itself lives on
## Combatant.weapon (a Weapon, not a Gear) and is never in this enum. Carries stat bonuses
## (Combatant.effective_stats() reads them, unchanged) plus reel affixes (shape only — no resolver
## wiring yet, no items authored).

enum Slot { HEADWEAR, CLOAK, CHEST, HANDS, CHARM }

@export var display_name: String = ""
@export var slot: Slot = Slot.CHEST
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON
@export var stat_bonuses: Stats
@export var reel_affixes: Array[ReelAffix] = []
