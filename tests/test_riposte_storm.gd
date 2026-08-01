extends SceneTree

## Skirmisher L4 "Riposte Storm" (task 19): a self-cast, NO-reel, ultimate-tier extra ability
## (3-turn CD) that detonates accumulated riposte_charges (built by Evasion, task 9/17) as a
## temporary Empowered (+15%/charge, capped at 5 charges = +75%, duration 1) on this turn's
## reels, then resets the charge counter to 0. Like Quickstep (task 18) / Mountain Stance
## (task 16) it only exercises the shared commit() dispatch — it does NOT touch
## REEL_ADDING_EXTRA_IDS/preview_reels (adds no reel).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _empowered_magnitude(c: Combatant) -> float:
	for e: Effect in c.active_effects:
		if e.id == &"empowered":
			return e.magnitude
	return -1.0

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"skirmisher")

	# Below unlock level: not stageable even though everything else is fine.
	var early_c: Combatant = cc.build_combatant(true)
	early_c.level = 3
	var early_plan: MainPhasePlan = MainPhasePlan.new(early_c)
	_check(not early_plan.can_stage_extra_ability(&"riposte_storm"), "not stageable below level 4")

	var c: Combatant = cc.build_combatant(true)
	c.level = 4
	# Riposte Storm costs 4 stamina but Skirmisher's start_stamina is only 3 [ASSUMPTION] — top up
	# to max_stamina so the affordable-path assertions actually exercise "affordable".
	c.resource_pool.stamina = c.resource_pool.max_stamina
	var starting_stamina: int = c.resource_pool.stamina
	c.riposte_charges = 3

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"riposte_storm"), "stageable at level 4, affordable, no CD")

	plan.toggle_extra_ability(&"riposte_storm")
	_check(plan.staged_extra_ability_id == &"riposte_storm", "toggle stages riposte_storm")

	var before_reel_count: int = c.turn_reels.size()
	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff)")
	_check(c.has_effect(&"empowered"), "commit attaches Empowered")
	_check(is_equal_approx(_empowered_magnitude(c), 1.60), "commit's Empowered magnitude is 1.60 (1.0 + 0.20*3)")
	_check(c.riposte_charges == 0, "commit reset riposte_charges to 0")
	var def: AbilityDef = c.find_extra_ability(&"riposte_storm")
	_check(c.resource_pool.stamina == starting_stamina - def.cost, "commit spent the ability's stamina cost (4)")
	_check(c.is_on_cooldown(&"riposte_storm"), "commit put the L4 ability on cooldown")

	# Direct Combatant-method checks, including the +5-charge cap.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.stamina = direct_c.resource_pool.max_stamina
	var direct_before_stamina: int = direct_c.resource_pool.stamina
	direct_c.riposte_charges = 10  # above the cap
	_check(direct_c.fire_riposte_storm(4), "fire_riposte_storm succeeds when affordable")
	_check(is_equal_approx(_empowered_magnitude(direct_c), 2.00), "fire_riposte_storm caps magnitude at 2.00 (1.0 + 0.20*5), not higher")
	_check(direct_c.riposte_charges == 0, "fire_riposte_storm reset riposte_charges to 0")
	_check(direct_c.resource_pool.stamina == direct_before_stamina - 4, "fire_riposte_storm spent 4 stamina")

	# Baseline: 0 charges -> magnitude 1.0 (no bonus, but still fires).
	var zero_c: Combatant = cc.build_combatant(true)
	zero_c.resource_pool.stamina = zero_c.resource_pool.max_stamina
	_check(zero_c.fire_riposte_storm(4), "fire_riposte_storm succeeds at 0 charges")
	_check(is_equal_approx(_empowered_magnitude(zero_c), 1.0), "fire_riposte_storm magnitude is 1.0 at 0 charges (baseline, no bonus)")

	# Affordability: 0 stamina -> refused, no change.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.resource_pool.stamina = 0
	poor_c.riposte_charges = 3
	_check(not poor_c.fire_riposte_storm(4), "fire_riposte_storm fails when unaffordable")
	_check(not poor_c.has_effect(&"empowered"), "no Empowered attached on a failed (unaffordable) cast")
	_check(poor_c.riposte_charges == 3, "riposte_charges unchanged on a failed cast")

	quit()
