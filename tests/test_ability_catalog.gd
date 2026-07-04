extends SceneTree

## Catalog completeness: every ability id any class ships (base ability_id + all extra_abilities)
## must have a non-empty display name AND description — catches a forgotten catalog entry whenever
## a future ability is added (spec 2026-07-02 §4).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var class_ids: Array[StringName] = [&"warrior", &"vanguard", &"skirmisher", &"chancer", &"ranger", &"seer", &"warden"]
	var seen: int = 0
	for cid: StringName in class_ids:
		var cc: CharacterClass = ClassLibrary.make(cid)
		var ids: Array[StringName] = [cc.ability_id]
		for def: AbilityDef in cc.extra_abilities:
			ids.append(def.id)
		for id: StringName in ids:
			seen += 1
			_check(AbilityCatalog.display_name(id) != "", "%s/%s: display_name non-empty" % [cid, id])
			_check(AbilityCatalog.description(id) != "", "%s/%s: description non-empty" % [cid, id])
	_check(seen == 28, "roster carries 28 ability ids (7 base + 21 extra), saw %d" % seen)
	_check(AbilityCatalog.display_name(&"nope") == "", "unknown id -> empty name")
	_check(AbilityCatalog.description(&"nope") == "", "unknown id -> empty description")
	quit()
