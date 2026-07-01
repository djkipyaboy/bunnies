extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.level = 9
	c.resource_pool = ResourcePool.new()
	c.resource_pool.stamina = 5; c.resource_pool.max_stamina = 5
	var a: AbilityDef = AbilityDef.new(); a.id = &"second_wind"; a.unlock_level = 9; a.cost = 5; a.resource = &"stamina"; a.cooldown_turns = 4
	c.extra_abilities = [a]

	_check(not c.is_on_cooldown(&"second_wind"), "not on cooldown initially")
	c.start_cooldown(&"second_wind", 4)
	_check(c.is_on_cooldown(&"second_wind"), "on cooldown after start_cooldown")
	for i in range(3):
		c.tick_cooldowns()
	_check(c.is_on_cooldown(&"second_wind"), "still on cooldown after 3 ticks (started at 4)")
	c.tick_cooldowns()
	_check(not c.is_on_cooldown(&"second_wind"), "off cooldown after the 4th tick")

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"second_wind"), "stageable: unlocked, affordable, no CD")
	c.start_cooldown(&"second_wind", 4)
	_check(not plan.can_stage_extra_ability(&"second_wind"), "not stageable while on cooldown")
	c.cooldowns.clear()
	c.level = 1
	_check(not plan.can_stage_extra_ability(&"second_wind"), "not stageable below unlock level")
	c.level = 9
	plan.toggle_extra_ability(&"second_wind")
	_check(plan.staged_extra_ability_id == &"second_wind", "toggle stages the extra ability")
	plan.toggle_ability()  # staging the (empty) base ability slot must clear the extra slot
	_check(plan.staged_extra_ability_id == &"", "staging the base ability clears the extra slot")
	quit()
