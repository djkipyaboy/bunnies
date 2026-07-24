extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.level = 10
	c.passive_ability_id = &"does_not_exist_yet"
	_check(c.passive_outgoing_multiplier() == 1.0, "unknown passive id is a neutral outgoing multiplier")
	_check(c.passive_incoming_multiplier() == 1.0, "unknown passive id is a neutral incoming multiplier")
	_check(c.passive_dot_damage_multiplier() == 1.0, "unknown passive id is a neutral DoT multiplier")
	_check(c.passive_max_mana_multiplier() == 1.0, "unknown passive id is a neutral max-mana multiplier")
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)  # must not crash with no bonus_meter

	var below5: Combatant = Combatant.new()
	below5.level = 4
	below5.passive_ability_id = &"anything"
	_check(below5.passive_outgoing_multiplier() == 1.0, "below L5, passive dispatch is skipped entirely")
	quit()
