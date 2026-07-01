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

	# Real-class scenario: a non-empty base ability_id whose stage attempt FAILS (unaffordable).
	# A failed toggle_ability() attempt must NOT silently clear an already-staged extra ability
	# (2026-07-01 finding on commit 76e4099 — toggle_ability() was clearing on any attempt, not
	# just successful ones, unlike the mirror-image toggle_extra_ability()).
	c.ability_id = &"flurry"
	c.ability_cost = 0  # unused directly by MainPhasePlan (it takes its own p_ability_cost), set for clarity
	var expensive_plan: MainPhasePlan = MainPhasePlan.new(c, 99)  # ability_cost=99, unaffordable vs. 5 stamina
	expensive_plan.staged_extra_ability_id = &"second_wind"
	_check(not expensive_plan.can_stage_ability(), "sanity: the base ability is unaffordable")
	expensive_plan.toggle_ability()
	_check(expensive_plan.staged_extra_ability_id == &"second_wind", "failed base-ability stage does NOT clear the extra slot")
	_check(not expensive_plan.ability_staged, "failed base-ability stage does not stage the base ability either")

	# Contrast case: staging a real, AFFORDABLE base ability successfully DOES clear the extra slot.
	var affordable_plan: MainPhasePlan = MainPhasePlan.new(c, 2)  # ability_cost=2, affordable vs. 5 stamina
	affordable_plan.staged_extra_ability_id = &"second_wind"
	affordable_plan.toggle_ability()
	_check(affordable_plan.ability_staged, "successful base-ability stage sets ability_staged")
	_check(affordable_plan.staged_extra_ability_id == &"", "successful base-ability stage clears the extra slot")

	quit()
