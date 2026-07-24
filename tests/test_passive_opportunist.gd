extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"opportunist"
	c.level = 5

	var defender: Combatant = Combatant.new()
	_check(c.passive_outgoing_multiplier(defender) == 1.0, "Opportunist: neutral vs an undebuffed defender")

	defender.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.passive_outgoing_multiplier(defender) == 1.15, "Opportunist: +15% vs a Slowed defender")

	var defender2: Combatant = Combatant.new()
	defender2.attach_effect(EffectLibrary.make(&"rooted"))
	_check(c.passive_outgoing_multiplier(defender2) == 1.15, "Opportunist: +15% vs a Rooted defender")

	var defender3: Combatant = Combatant.new()
	defender3.stunned_last_turn = true
	_check(c.passive_outgoing_multiplier(defender3) == 1.15, "Opportunist: +15% vs a defender stunned last turn")

	_check(c.passive_outgoing_multiplier(null) == 1.0, "Opportunist: neutral with no defender reference")

	var sc: CharacterClass = ClassLibrary.make(&"skirmisher")
	_check(sc.passive_ability_id == &"opportunist", "Skirmisher's CharacterClass carries the passive id")
	quit()
