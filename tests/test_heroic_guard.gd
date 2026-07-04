extends SceneTree

## Warrior L7 "Heroic Guard" (spec 2026-07-01 §4B, task 12): a self-cast, NO-reel extra ability that
## grants Guarded + Taunt so he pulls fire off fragile allies. Unlike Sundering Strike (task 11) this
## does NOT touch REEL_ADDING_EXTRA_IDS/preview_reels — it only exercises the shared commit() dispatch.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"warrior")
	var c: Combatant = cc.build_combatant(true)

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"heroic_guard"), "not stageable below level 7")

	c.level = 7
	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"heroic_guard"), "stageable at level 7, affordable, no CD")

	plan.toggle_extra_ability(&"heroic_guard")
	_check(plan.staged_extra_ability_id == &"heroic_guard", "toggle stages heroic_guard")

	var before_reel_count: int = c.turn_reels.size()
	var before_stamina: int = c.resource_pool.stamina

	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff, unlike Sundering Strike)")
	_check(c.has_effect(&"guarded"), "commit attaches Guarded")
	_check(c.has_effect(&"taunt"), "commit attaches Taunt")
	_check(c.resource_pool.stamina == before_stamina - 3, "commit spent the ability's stamina cost (3)")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 7
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"heroic_guard"), "not stageable with 0 stamina")

	# Direct Combatant-method checks.
	var direct_c: Combatant = cc.build_combatant(true)
	var direct_before_stamina: int = direct_c.resource_pool.stamina
	_check(direct_c.apply_heroic_guard(3), "apply_heroic_guard succeeds when affordable")
	_check(direct_c.has_effect(&"guarded"), "apply_heroic_guard attached Guarded")
	_check(direct_c.has_effect(&"taunt"), "apply_heroic_guard attached Taunt")
	_check(direct_c.resource_pool.stamina == direct_before_stamina - 3, "apply_heroic_guard spent stamina")
	_check(not direct_c.apply_heroic_guard(999), "apply_heroic_guard fails when unaffordable")

	quit()
