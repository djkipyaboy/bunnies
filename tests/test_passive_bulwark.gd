extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"bulwark"
	c.level = 5
	c.max_hp = 100
	c.hp = 51
	_check(c.passive_incoming_multiplier() == 0.85, "Bulwark: -15% just above 50% HP")
	c.hp = 50
	_check(c.passive_incoming_multiplier() == 1.0, "Bulwark: neutral at exactly 50% HP (threshold is exclusive)")
	c.level = 4
	c.hp = 100
	_check(c.passive_incoming_multiplier() == 1.0, "Bulwark: inactive below L5 even at full HP")

	var vc: CharacterClass = ClassLibrary.make(&"vanguard")
	_check(vc.passive_ability_id == &"bulwark", "Vanguard's CharacterClass carries the passive id")
	quit()
