extends SceneTree

## Warrior L4 "Second Wind" (spec 2026-07-01 §4B, task 13): a self-cast, NO-reel, ultimate-tier
## extra ability (4-turn CD) that heals 30% max HP (ceil), Cleanses every debuff, and grants
## Guarded. First real exercise of the cooldown system (Task 3) inside an actual ability commit —
## verifies the generic "if def.cooldown_turns > 0: start_cooldown(...)" line in commit() (Task 11)
## fires for Second Wind too, not just Sundering Strike.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"warrior")
	var c: Combatant = cc.build_combatant(true)

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"second_wind"), "not stageable below level 4")

	c.level = 4
	# Second Wind costs 5 stamina, more than the Warrior's start_stamina (3) but within max_stamina
	# (6 = base 5 + Focus 1) — top up to max to model a mid-fight combatant reaching for the L4
	# ultimate-tier ability after some Upkeep regen, rather than the fresh-combat starting pool.
	c.resource_pool.stamina = c.resource_pool.max_stamina
	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"second_wind"), "stageable at level 4, affordable, no CD")

	# Damage the combatant and attach a debuff so healing/cleanse have something to undo.
	c.hp = 10
	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.has_effect(&"slow"), "sanity: slow attached before commit")

	plan.toggle_extra_ability(&"second_wind")
	_check(plan.staged_extra_ability_id == &"second_wind", "toggle stages second_wind")

	var before_reel_count: int = c.turn_reels.size()
	var before_stamina: int = c.resource_pool.stamina

	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast, like Heroic Guard)")
	# c.max_hp is base_max_hp (300) + Vigor from base_stats (apply_stats(), called by build_combatant) —
	# use the live derived value rather than hardcoding 300 so this test tracks the class data.
	_check(c.hp == 10 + ceili(c.max_hp * 0.30), "commit healed 30% of max HP (ceil) on top of existing HP")
	_check(not c.has_effect(&"slow"), "commit cleansed the slow debuff")
	_check(c.has_effect(&"guarded"), "commit attached Guarded")
	_check(c.resource_pool.stamina == before_stamina - 5, "commit spent the ability's stamina cost (5)")
	_check(c.is_on_cooldown(&"second_wind"), "commit started the 4-turn cooldown (Task 11's generic line fires here too)")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 4
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"second_wind"), "not stageable with 0 stamina")

	# Direct Combatant-method checks.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.stamina = direct_c.resource_pool.max_stamina  # needs 5; start_stamina is only 3
	direct_c.hp = 10
	direct_c.attach_effect(EffectLibrary.make(&"slow"))
	var direct_before_stamina: int = direct_c.resource_pool.stamina
	_check(direct_c.apply_second_wind(5), "apply_second_wind succeeds when affordable")
	_check(direct_c.hp == 10 + ceili(direct_c.max_hp * 0.30), "apply_second_wind healed 30% max HP (ceil)")
	_check(not direct_c.has_effect(&"slow"), "apply_second_wind cleansed the slow debuff")
	_check(direct_c.has_effect(&"guarded"), "apply_second_wind attached Guarded")
	_check(direct_c.resource_pool.stamina == direct_before_stamina - 5, "apply_second_wind spent stamina")
	_check(not direct_c.apply_second_wind(999), "apply_second_wind fails when unaffordable")

	quit()
