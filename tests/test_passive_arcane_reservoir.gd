extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"arcane_reservoir"
	c.level = 5
	c.base_max_mana = 20
	c.resource_pool = ResourcePool.new()
	c.apply_stats()
	_check(c.resource_pool.max_mana == 24, "Arcane Reservoir: +20% max Mana (20 -> 24)")

	c.level = 4
	c.apply_stats()
	_check(c.resource_pool.max_mana == 20, "Arcane Reservoir: inactive below L5")

	var sc: CharacterClass = ClassLibrary.make(&"seer")
	_check(sc.passive_ability_id == &"arcane_reservoir", "Seer's CharacterClass carries the passive id")
	quit()
