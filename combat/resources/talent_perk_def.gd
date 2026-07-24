class_name TalentPerkDef
extends Resource

## Track B (Universal Perks, spec 2026-07-24 §4) — one entry per perk. A flat-stat perk sets
## stat_key/stat_amount and is applied generically via Combatant.talent_stat_bonuses(); a bespoke
## perk (deep_reserves/sharp_reflexes/thick_skin/battle_hardened) leaves stat_key empty and is
## instead checked by id at its own dedicated hook (same convention as passives).
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var stat_key: StringName = &""
@export var stat_amount: int = 0
