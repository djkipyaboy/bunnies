class_name AbilityTalentLibrary
extends RefCounted

## Code registry of Track A's 126 options (spec 2026-07-24 §3/§5 — 6 rows × 3 options × 7 classes).
## Mirrors ClassLibrary/TalentPerkLibrary: returns a FRESH Array each call. Empty per class until
## Tasks 15-21 populate real content — NOT a placeholder, a genuinely correct empty state (mirrors
## Task 3's passive scaffolding preceding Tasks 5-11's real per-class content).
const ROW_IDS: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]

static func options_for(class_id: StringName, row_id: StringName) -> Array[AbilityTalentOption]:
	match class_id:
		_:
			return []

static func _opt(id: StringName, dname: String, desc: String) -> AbilityTalentOption:
	var o: AbilityTalentOption = AbilityTalentOption.new()
	o.id = id; o.display_name = dname; o.description = desc
	return o
