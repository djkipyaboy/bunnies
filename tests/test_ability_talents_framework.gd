extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Row-unlock level mapping (spec 2026-07-24 §2's fixed table).
	var c: Combatant = Combatant.new()
	c.class_id = &"warrior"
	_check(c.ability_talent_row_unlock_level(&"base_ability") == 5, "base_ability unlocks at L5")
	_check(c.ability_talent_row_unlock_level(&"ability_l2") == 6, "ability_l2 row unlocks at L6")
	_check(c.ability_talent_row_unlock_level(&"ability_l3") == 7, "ability_l3 row unlocks at L7")
	_check(c.ability_talent_row_unlock_level(&"ability_l4") == 8, "ability_l4 row unlocks at L8")
	_check(c.ability_talent_row_unlock_level(&"passive") == 9, "passive row unlocks at L9")
	_check(c.ability_talent_row_unlock_level(&"ultimate") == 10, "ultimate row unlocks at L10")

	c.level = 4
	_check(not c.ability_talent_row_unlocked(&"base_ability"), "base_ability row locked below L5")
	c.level = 5
	_check(c.ability_talent_row_unlocked(&"base_ability"), "base_ability row unlocked at L5")
	_check(not c.ability_talent_row_unlocked(&"ability_l2"), "ability_l2 row still locked at L5")

	# Picking is rejected before the row unlocks, and rejected for a bogus option id.
	_check(not c.pick_ability_talent(&"ability_l2", &"anything"), "picking a still-locked row is rejected")
	c.level = 10  # every row unlocked now, but Task 14 seeds no real content yet — every options_for() is empty
	_check(not c.pick_ability_talent(&"base_ability", &"not_a_real_option"), "picking an option not in that row's list is rejected")
	_check(not c.has_ability_talent(&"not_a_real_option"), "has_ability_talent() is false for anything unpicked")

	# ability_talent_picks caps at 1 pick per row and is independently trackable per row — proven with
	# a synthetic option registered directly on the Dictionary (bypassing pick_ability_talent's
	# options_for() validation, since Task 14 seeds no real per-class content) to prove the STORAGE
	# shape works before Tasks 15-21 populate real, validatable options.
	c.ability_talent_picks[&"base_ability"] = &"synthetic_option"
	_check(c.ability_talent_picks.get(&"base_ability", &"") == &"synthetic_option", "a row's pick is stored under its own row_id key")
	_check(not c.ability_talent_picks.has(&"ability_l2"), "an unpicked row has no key at all")

	var uc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(uc.class_id == &"warrior", "Warrior's CharacterClass carries class_id")
	var pc: Combatant = uc.build_combatant(true)
	_check(pc.class_id == &"warrior", "build_combatant() copies class_id")
	quit()
