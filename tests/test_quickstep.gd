extends SceneTree

## Skirmisher L3 "Quickstep" (task 18): a self-cast, NO-reel extra ability that grants Haste (a
## one-time +20 initiative bump via the &"haste" INITIATIVE_MOD effect). Like Feint & Riposte
## (task 17) it only exercises the shared commit() dispatch; it does NOT touch
## REEL_ADDING_EXTRA_IDS/preview_reels (adds no reel).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"skirmisher")

	# Below unlock level: not stageable even though everything else is fine.
	var early_c: Combatant = cc.build_combatant(true)
	early_c.level = 2
	var early_plan: MainPhasePlan = MainPhasePlan.new(early_c)
	_check(not early_plan.can_stage_extra_ability(&"quickstep"), "not stageable below level 3")

	var c: Combatant = cc.build_combatant(true)
	c.level = 3
	# Quickstep costs 3 stamina but Skirmisher's start_stamina is only 3 [ASSUMPTION] — top up to
	# max_stamina so the affordable-path assertions actually exercise "affordable".
	c.resource_pool.stamina = c.resource_pool.max_stamina
	var starting_stamina: int = c.resource_pool.stamina
	var initiative_before: int = c.current_initiative

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"quickstep"), "stageable at level 3, affordable, no CD")

	plan.toggle_extra_ability(&"quickstep")
	_check(plan.staged_extra_ability_id == &"quickstep", "toggle stages quickstep")

	var before_reel_count: int = c.turn_reels.size()
	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff)")
	_check(c.has_effect(&"haste"), "commit attaches Haste")
	_check(c.current_initiative == initiative_before + 20, "commit raised current_initiative by exactly 20")
	var def: AbilityDef = c.find_extra_ability(&"quickstep")
	_check(c.resource_pool.stamina == starting_stamina - def.cost, "commit spent the ability's stamina cost (3)")

	# Direct Combatant-method checks.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.stamina = direct_c.resource_pool.max_stamina
	var direct_before_stamina: int = direct_c.resource_pool.stamina
	var direct_before_init: int = direct_c.current_initiative
	_check(direct_c.apply_quickstep(3), "apply_quickstep succeeds when affordable")
	_check(direct_c.has_effect(&"haste"), "apply_quickstep attached Haste")
	_check(direct_c.current_initiative == direct_before_init + 20, "apply_quickstep raised current_initiative by exactly 20")
	_check(direct_c.resource_pool.stamina == direct_before_stamina - 3, "apply_quickstep spent 3 stamina")

	# Affordability: 0 stamina -> refused, no change.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.resource_pool.stamina = 0
	var poor_before_init: int = poor_c.current_initiative
	_check(not poor_c.apply_quickstep(3), "apply_quickstep fails when unaffordable")
	_check(not poor_c.has_effect(&"haste"), "no Haste attached on a failed (unaffordable) cast")
	_check(poor_c.current_initiative == poor_before_init, "current_initiative unchanged on a failed cast")

	quit()
