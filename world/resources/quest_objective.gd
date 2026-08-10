class_name QuestObjective
extends Resource

## One step within a Quest's objectives array (2026-08-10 quest-system-and-tutorial design §3).
## Data only — completion is tracked externally by PartyInventory.is_objective_complete().

@export var id: StringName = &""
@export var display_text: String = ""
