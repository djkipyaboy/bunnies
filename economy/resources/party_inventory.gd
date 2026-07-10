class_name PartyInventory
extends Resource

## One shared inventory per PC (not per-companion) — spec 2026-07-10 §4.1. Weightless; only the
## Gear tab is slot-capped (a soft friction lever toward banking/selling, not a hard wall).
## Materials/Reel-Mods/Quest stay uncapped. `unlocked_companion_slots` increments PERMANENTLY at
## story beats regardless of whether a companion currently occupies the slot.

const BASE_GEAR_CAPACITY: int = 20
const GEAR_CAPACITY_PER_SLOT: int = 10

@export var gear: Array[Gear] = []
@export var reel_mods: Array[Resource] = []    # uncapped; shape TBD when 27-crafting is designed
@export var materials: Array[Resource] = []    # uncapped, stacking
@export var quest_items: Array[Resource] = []  # uncapped; never banked (per-playthrough only)
@export var gold: int = 0
@export var unlocked_companion_slots: int = 0  # 0-2, story-gated

func gear_capacity() -> int:
	return BASE_GEAR_CAPACITY + GEAR_CAPACITY_PER_SLOT * unlocked_companion_slots

func can_add_gear() -> bool:
	return gear.size() < gear_capacity()
