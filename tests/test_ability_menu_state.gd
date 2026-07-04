extends SceneTree

## Pure row-state logic for the ability menu (spec 2026-07-02 §2 table) — every state, no scene tree.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_combatant() -> Combatant:
	var c: Combatant = Combatant.new()
	c.is_player = true
	c.level = 9
	c.ability_id = &"flurry"
	c.ability_resource = &"stamina"
	c.resource_pool = ResourcePool.new()
	c.resource_pool.stamina = 10
	c.resource_pool.max_stamina = 10
	var a: AbilityDef = AbilityDef.new()
	a.id = &"riposte_storm"; a.unlock_level = 9; a.cost = 4; a.resource = &"stamina"; a.cooldown_turns = 3
	c.extra_abilities = [a]
	return c

func _init() -> void:
	var c: Combatant = _make_combatant()
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2)

	# Base-ability states.
	_check(AbilityMenuPanel.row_state(plan, c, &"flurry") == AbilityMenuPanel.RowState.NORMAL, "base: NORMAL when stageable")
	plan.toggle_ability()
	_check(AbilityMenuPanel.row_state(plan, c, &"flurry") == AbilityMenuPanel.RowState.STAGED, "base: STAGED after toggle")
	plan.toggle_ability()
	c.resource_pool.stamina = 0
	_check(AbilityMenuPanel.row_state(plan, c, &"flurry") == AbilityMenuPanel.RowState.UNAFFORDABLE, "base: UNAFFORDABLE at 0 STA")
	c.resource_pool.stamina = 10

	# Extra-ability states.
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.NORMAL, "extra: NORMAL when stageable")
	plan.toggle_extra_ability(&"riposte_storm")
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.STAGED, "extra: STAGED after toggle")
	plan.toggle_extra_ability(&"riposte_storm")
	c.start_cooldown(&"riposte_storm", 3)
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.ON_COOLDOWN, "extra: ON_COOLDOWN")
	_check(AbilityMenuPanel.cooldown_text(c, &"riposte_storm") == "On cooldown: 3 turns", "cooldown text shows remaining turns")
	c.cooldowns.clear()
	_check(AbilityMenuPanel.cooldown_text(c, &"riposte_storm") == "Ready — 3-turn cooldown after use", "L9 off-cooldown text warns of CD")
	c.resource_pool.stamina = 0
	_check(AbilityMenuPanel.row_state(plan, c, &"riposte_storm") == AbilityMenuPanel.RowState.UNAFFORDABLE, "extra: UNAFFORDABLE at 0 STA")
	c.resource_pool.stamina = 10

	# LOCKED_BY_ULTIMATE: Chancer's Wildcard Gamble subsumes Re-roll.
	var chancer: Combatant = _make_combatant()
	chancer.ability_id = &"reroll"
	chancer.ultimate_id = &"wildcard_gamble"
	var plan2: MainPhasePlan = MainPhasePlan.new(chancer, 4)
	plan2.fire_ultimate_staged = true
	_check(AbilityMenuPanel.row_state(plan2, chancer, &"reroll") == AbilityMenuPanel.RowState.LOCKED_BY_ULTIMATE, "base: LOCKED_BY_ULTIMATE under Wildcard Gamble")

	# INCLUDED_FREE: Vanguard's Rampage bakes in Heft.
	var van: Combatant = _make_combatant()
	van.ability_id = &"heft"
	van.ultimate_id = &"rampage"
	var plan3: MainPhasePlan = MainPhasePlan.new(van, 2)
	plan3.fire_ultimate_staged = true
	_check(AbilityMenuPanel.row_state(plan3, van, &"heft") == AbilityMenuPanel.RowState.INCLUDED_FREE, "base: INCLUDED_FREE under Rampage")

	# Cost text: base from the plan's rail/cost, extra from its AbilityDef, all-in special case.
	_check(AbilityMenuPanel.cost_text(plan, c, &"flurry") == "2 STA", "base cost text")
	_check(AbilityMenuPanel.cost_text(plan, c, &"riposte_storm") == "4 STA", "extra cost text")
	var don: AbilityDef = AbilityDef.new()
	don.id = &"double_or_nothing"; don.unlock_level = 9; don.cost = 0; don.resource = &"mana"; don.cooldown_turns = 7
	c.extra_abilities.append(don)
	_check(AbilityMenuPanel.cost_text(plan, c, &"double_or_nothing") == "all-in: ALL remaining Mana", "Double or Nothing cost text")
	var mana_c: Combatant = _make_combatant()
	mana_c.ability_id = &"rallying_cry"
	mana_c.ability_resource = &"mana"
	var plan4: MainPhasePlan = MainPhasePlan.new(mana_c, 4)
	_check(AbilityMenuPanel.cost_text(plan4, mana_c, &"rallying_cry") == "4 MANA", "mana rail cost text")
	_check(AbilityMenuPanel.cooldown_text(c, &"flurry") == "Ready", "base ability cooldown text is Ready")
	quit()
