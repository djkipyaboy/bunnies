class_name AbilityDef
extends Resource

## One NEW (L5/L7/L9) per-class ability's data (spec 2026-07-01). Parallel to the existing single
## CharacterClass.ability_id/ability_cost/ability_resource fields (the L1 ability), which are
## untouched — see plan "Corrections to the locked spec" §1.

@export var id: StringName = &""
@export var unlock_level: int = 1
@export var cost: int = 2
@export var resource: StringName = &"stamina"

## 0 = no cooldown (L5/L7 abilities). L9 abilities set this (spec §4).
@export var cooldown_turns: int = 0
