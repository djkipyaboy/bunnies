extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"last_stand"
	c.level = 5
	c.max_hp = 100
	c.hp = 30  # exactly 30% — the threshold is inclusive
	_check(c.passive_outgoing_multiplier() == 1.2, "Last Stand: +20% at exactly 30% HP")
	c.hp = 31
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: neutral just above 30% HP")
	c.level = 4
	c.hp = 10
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: inactive below L5 even at low HP")

	var wc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(wc.passive_ability_id == &"last_stand", "Warrior's CharacterClass carries the passive id")
	var pc: Combatant = wc.build_combatant(true)
	_check(pc.passive_ability_id == &"last_stand", "build_combatant() copies passive_ability_id")
	quit()
