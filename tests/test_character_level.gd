extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.level = 5
	var a5: AbilityDef = AbilityDef.new(); a5.id = &"a5"; a5.unlock_level = 5
	var a7: AbilityDef = AbilityDef.new(); a7.id = &"a7"; a7.unlock_level = 7
	var a9: AbilityDef = AbilityDef.new(); a9.id = &"a9"; a9.unlock_level = 9
	c.extra_abilities = [a5, a7, a9]
	var unlocked: Array[AbilityDef] = c.unlocked_extra_abilities()
	_check(unlocked.size() == 1 and unlocked[0].id == &"a5", "level 5 unlocks only a5")
	c.level = 9
	_check(c.unlocked_extra_abilities().size() == 3, "level 9 unlocks all three")
	_check(c.find_extra_ability(&"a7").cost == 2, "find_extra_ability returns the def (default cost 2)")
	_check(c.find_extra_ability(&"nope") == null, "find_extra_ability null for unknown id")

	var cc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(cc.extra_abilities.size() == 3, "Warrior has 3 extra_abilities authored")
	var pc: Combatant = cc.build_combatant(true)
	_check(pc.extra_abilities.size() == 3, "build_combatant copies extra_abilities")
	_check(pc.level == 1, "build_combatant defaults level to 1")
	quit()
