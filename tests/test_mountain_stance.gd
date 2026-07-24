extends SceneTree

## Vanguard L4 "Mountain Stance" (spec/task 16): a self-cast, NO-reel, ultimate-tier extra ability
## (4-turn CD) that grants a heavy Guarded (incoming ×0.5) + full immunity to Slow/Rooted/Stunned +
## a Taunt for 3 turns. Like Bloodwrath (task 14) / Heroic Guard (task 12) it only exercises the shared
## commit() dispatch; it does NOT touch REEL_ADDING_EXTRA_IDS/preview_reels. This is the FIRST ability
## to exercise Effect.immune_effect_ids + Effect.grants_stun_immunity (added in task 4).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"vanguard")

	# Below unlock level: not stageable even though everything else is fine.
	var early_c: Combatant = cc.build_combatant(true)
	early_c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(early_c)
	_check(not early_plan.can_stage_extra_ability(&"mountain_stance"), "not stageable below level 4")

	var c: Combatant = cc.build_combatant(true)
	c.level = 4
	# Mountain Stance costs 5 stamina but Vanguard's start_stamina is only 3 [ASSUMPTION] — top up to
	# max_stamina so the affordable-path assertions actually exercise "affordable".
	c.resource_pool.stamina = c.resource_pool.max_stamina
	var starting_stamina: int = c.resource_pool.stamina

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"mountain_stance"), "stageable at level 4, affordable, no CD")

	plan.toggle_extra_ability(&"mountain_stance")
	_check(plan.staged_extra_ability_id == &"mountain_stance", "toggle stages mountain_stance")

	var before_reel_count: int = c.turn_reels.size()
	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff)")
	_check(c.has_effect(&"guarded"), "commit attaches Guarded")
	_check(c.has_effect(&"taunt"), "commit attaches Taunt")
	var def: AbilityDef = c.find_extra_ability(&"mountain_stance")
	_check(c.resource_pool.stamina == starting_stamina - def.cost, "commit spent the ability's stamina cost (5)")
	_check(c.is_on_cooldown(&"mountain_stance"), "commit put the L4 ability on cooldown")

	# Heavy Guarded: incoming damage is halved (magnitude overridden to 0.5, not the 0.75 default).
	_check(is_equal_approx(c.incoming_damage_multiplier(), 0.5), "incoming_damage_multiplier == 0.5 (heavy Guarded)")

	# Slow immunity: attaching Slow is refused entirely while the guard's immunity is active.
	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(not c.has_effect(&"slow"), "Slow attach blocked by immunity")
	# Rooted immunity too (both listed in immune_effect_ids).
	c.attach_effect(EffectLibrary.make(&"rooted"))
	_check(not c.has_effect(&"rooted"), "Rooted attach blocked by immunity")

	# Stun immunity: a crushingly low initiative would normally STUN, but grants_stun_immunity overrides.
	c.base_initiative = 0
	c.recompute_initiative()
	_check(not c.evaluate_stun(999), "evaluate_stun returns false despite low initiative (stun immunity)")

	# Direct Combatant-method checks.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.stamina = direct_c.resource_pool.max_stamina
	var direct_before: int = direct_c.resource_pool.stamina
	_check(direct_c.apply_mountain_stance(5), "apply_mountain_stance succeeds when affordable")
	_check(direct_c.has_effect(&"guarded") and direct_c.has_effect(&"taunt"), "apply_mountain_stance attached Guarded + Taunt")
	_check(direct_c.resource_pool.stamina == direct_before - 5, "apply_mountain_stance spent 5 stamina")
	_check(is_equal_approx(direct_c.incoming_damage_multiplier(), 0.5), "direct: incoming multiplier 0.5")

	# Affordability: 0 stamina -> refused, no change.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.resource_pool.stamina = 0
	_check(not poor_c.apply_mountain_stance(5), "apply_mountain_stance fails when unaffordable")
	_check(not poor_c.has_effect(&"guarded"), "no Guarded attached on a failed (unaffordable) cast")

	quit()
