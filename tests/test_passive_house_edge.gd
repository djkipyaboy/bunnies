extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"house_edge"
	c.level = 5
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 15
	var before: int = c.bonus_meter.value
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c.bonus_meter.value == before + 1, "House Edge: +1 flat meter charge on any scored payline")

	c.level = 4
	var before2: int = c.bonus_meter.value
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c.bonus_meter.value == before2, "House Edge: inactive below L5")

	var no_meter: Combatant = Combatant.new()
	no_meter.passive_ability_id = &"house_edge"
	no_meter.level = 5
	no_meter.passive_on_payline_scored(ReelFace.ResultTier.CRIT_SUCCESS)  # must not crash with null bonus_meter

	var cc: CharacterClass = ClassLibrary.make(&"chancer")
	_check(cc.passive_ability_id == &"house_edge", "Chancer's CharacterClass carries the passive id")
	quit()
