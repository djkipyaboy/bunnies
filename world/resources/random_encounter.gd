class_name RandomEncounter
extends Resource

## A Slay-the-Spire-style "?" overworld encounter (player direction 2026-07-12): a scenario with
## player-chosen options, each resolved via its own reel spin (see EncounterOption). Authored
## instances come from EncounterLibrary — this Resource is just the data shape.

@export var id: StringName = &""
@export var description: String = ""
@export var options: Array[EncounterOption] = []
