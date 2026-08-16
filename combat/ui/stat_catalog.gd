class_name StatCatalog
extends RefCounted

## Static stat-id -> player-facing display name + "what this does" description, for the six [Stats]
## fields (Stats.gd's own class docstring is the source of truth for the mapping; this catalog just
## turns that terse doc-comment into player-facing copy, mirroring AbilityCatalog's id->copy pattern).
## Used by CharacterCreationScreen's Species step so the player can see what a Heritage's passive
## stat bump actually affects before picking a race.

const ORDER: Array[StringName] = [&"might", &"finesse", &"vigor", &"focus", &"grit", &"luck"]

static func display_name(stat: StringName) -> String:
	match stat:
		&"might": return "Might"
		&"finesse": return "Finesse"
		&"vigor": return "Vigor"
		&"focus": return "Focus"
		&"grit": return "Grit"
		&"luck": return "Luck"
		_: return "?"

static func description(stat: StringName) -> String:
	match stat:
		&"might": return "Increases your outgoing damage."
		&"finesse": return "Improves initiative and turn-order tiebreaks, and converts some of your weapon's Fail faces into Success faces."
		&"vigor": return "Increases your maximum HP."
		&"focus": return "Increases your resource pool (Stamina/Mana)."
		&"grit": return "Raises your Bonus Meter's floor — how much charge you keep between fights."
		&"luck": return "Converts some of your weapon's Crit-Fail faces into Crit-Success faces."
		_: return ""
