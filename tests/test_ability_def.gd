extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var a: AbilityDef = AbilityDef.new()
	a.id = &"sundering_strike"
	a.unlock_level = 5
	a.cost = 3
	a.resource = &"stamina"
	a.cooldown_turns = 0
	_check(a.id == &"sundering_strike", "id set")
	_check(a.unlock_level == 5, "unlock_level set")
	_check(a.cooldown_turns == 0, "cooldown default path set")
	quit()
