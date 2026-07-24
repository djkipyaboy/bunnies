extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"steady_aim"
	c.level = 5

	var defender: Combatant = Combatant.new()
	_check(c.passive_outgoing_multiplier(defender) == 1.0, "Steady Aim: neutral vs an unmarked defender")

	defender.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(c.passive_outgoing_multiplier(defender) == 1.10, "Steady Aim: +10% vs a Marked defender")

	var rc: CharacterClass = ClassLibrary.make(&"ranger")
	_check(rc.passive_ability_id == &"steady_aim", "Ranger's CharacterClass carries the passive id")
	quit()
