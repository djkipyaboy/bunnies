extends SceneTree

## Skirmisher L2 "Feint & Riposte" (task 17): a self-cast, NO-reel extra ability that grants BOTH
## Evasion and Taunt at once — the bait-and-dodge setup for the later Riposte Storm (task 18). Like
## Mountain Stance (task 16) / Bloodwrath (task 14) it only exercises the shared commit() dispatch;
## it does NOT touch REEL_ADDING_EXTRA_IDS/preview_reels (adds no reel).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"skirmisher")

	# Below unlock level: not stageable even though everything else is fine.
	var early_c: Combatant = cc.build_combatant(true)
	early_c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(early_c)
	_check(not early_plan.can_stage_extra_ability(&"feint_riposte"), "not stageable below level 2")

	var c: Combatant = cc.build_combatant(true)
	c.level = 2
	# Feint & Riposte costs 3 stamina but Skirmisher's start_stamina is only 3 [ASSUMPTION] — top up to
	# max_stamina so the affordable-path assertions actually exercise "affordable".
	c.resource_pool.stamina = c.resource_pool.max_stamina
	var starting_stamina: int = c.resource_pool.stamina

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"feint_riposte"), "stageable at level 2, affordable, no CD")

	plan.toggle_extra_ability(&"feint_riposte")
	_check(plan.staged_extra_ability_id == &"feint_riposte", "toggle stages feint_riposte")

	var before_reel_count: int = c.turn_reels.size()
	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff)")
	_check(c.has_effect(&"evasion"), "commit attaches Evasion")
	_check(c.has_effect(&"taunt"), "commit attaches Taunt")
	var def: AbilityDef = c.find_extra_ability(&"feint_riposte")
	_check(c.resource_pool.stamina == starting_stamina - def.cost, "commit spent the ability's stamina cost (3)")

	# Direct Combatant-method checks.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.stamina = direct_c.resource_pool.max_stamina
	var direct_before: int = direct_c.resource_pool.stamina
	_check(direct_c.apply_feint_riposte(3), "apply_feint_riposte succeeds when affordable")
	_check(direct_c.has_effect(&"evasion") and direct_c.has_effect(&"taunt"), "apply_feint_riposte attached Evasion + Taunt")
	_check(direct_c.resource_pool.stamina == direct_before - 3, "apply_feint_riposte spent 3 stamina")

	# Affordability: 0 stamina -> refused, no change.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.resource_pool.stamina = 0
	_check(not poor_c.apply_feint_riposte(3), "apply_feint_riposte fails when unaffordable")
	_check(not poor_c.has_effect(&"evasion"), "no Evasion attached on a failed (unaffordable) cast")
	_check(not poor_c.has_effect(&"taunt"), "no Taunt attached on a failed (unaffordable) cast")

	quit()
