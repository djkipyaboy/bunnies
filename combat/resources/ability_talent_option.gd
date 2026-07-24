class_name AbilityTalentOption
extends Resource

## Track A (Ability Talents, spec 2026-07-24 §3) — one of a row's 3 options. Kept as its own
## resource (not reusing TalentPerkDef) since an ability-scoped option's effect is read at a
## specific bespoke hook (a per-class Combatant method), never a generic stat field.
@export var id: StringName = &""
## Which of the 6 fixed row ids (AbilityTalentLibrary.ROW_IDS) this option belongs to — set by
## whichever options_for() branch constructs it. Lets a caller (e.g. TalentMenuPanel, or a test)
## round-trip an option back to its row without a second lookup.
@export var row_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
