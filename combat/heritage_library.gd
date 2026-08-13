class_name HeritageLibrary
extends RefCounted

## Code registry of the First 9 playable species (docs/design-bible/10-storyline.md §6). Mirrors
## ClassLibrary: returns a FRESH Heritage each call. Passive stat/amount values are [ASSUMPTION]
## placeholders -- tune by a later design-bible content session (spec
## 2026-08-13-character-creation-design.md).

const IDS: Array[StringName] = [&"hare", &"otter", &"badger", &"mouse", &"frog", &"turtle", &"fox", &"weasel", &"wildcat"]

static func _make(species_name: String, passive_description: String, passive_stat: StringName, passive_stat_bonus: int) -> Heritage:
	var h: Heritage = Heritage.new()
	h.species_name = species_name
	h.passive_description = passive_description
	h.passive_stat = passive_stat
	h.passive_stat_bonus = passive_stat_bonus
	return h

static func make(id: StringName) -> Heritage:
	match id:
		&"hare": return _make("Hare", "+1 Finesse", &"finesse", 1)
		&"otter": return _make("Otter", "+1 Vigor", &"vigor", 1)
		&"badger": return _make("Badger", "+1 Might", &"might", 1)
		&"mouse": return _make("Mouse", "+1 Grit", &"grit", 1)
		&"frog": return _make("Frog", "+1 Focus", &"focus", 1)
		&"turtle": return _make("Turtle", "+1 Grit", &"grit", 1)
		&"fox": return _make("Fox", "+1 Luck", &"luck", 1)
		&"weasel": return _make("Weasel", "+1 Finesse", &"finesse", 1)
		&"wildcat": return _make("Wildcat", "+1 Might", &"might", 1)
		_: return null
