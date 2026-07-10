class_name Vault
extends Resource

## The account-wide, cross-character bank (spec §4.2) — the ONE thing shared across a player's
## multiple WoW-alt-style PCs. Finite, tab-based, expandable via a dual sink (story/mastery-earned
## early tabs, gold-bought later tabs — costs are content, out of scope this pass). No Quest tab:
## quest items are per-playthrough and never cross the party<->bank boundary.

@export var gear: Array[Gear] = []
@export var reel_mods: Array[Resource] = []
@export var materials: Array[Resource] = []
@export var tab_capacity: Dictionary = {}   # StringName tab name -> int capacity

func capacity_for(tab: StringName) -> int:
	return tab_capacity.get(tab, 0)

func can_add(tab: StringName, list: Array) -> bool:
	return list.size() < capacity_for(tab)
