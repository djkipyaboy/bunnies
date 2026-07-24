extends SceneTree

## Vanguard L3 "Quake Slam" (spec 2026-07-01 §4B, task 15): a reel-adding extra ability that
## splices one real-damage weapon-type reel whose hit faces also carry the &"slow" rider —
## mirrors Task 11's Sundering Strike shape/plumbing (REEL_ADDING_EXTRA_IDS cap-check + preview +
## commit), reusing the pre-existing Crushing->Slow &"slow" rider instead of &"sundered".

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"vanguard")
	var c: Combatant = cc.build_combatant(true)
	c.level = 3

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"quake_slam"), "not stageable below level 3")
	c.level = 3

	# Quake Slam costs 4 stamina but Vanguard's start_stamina is only 3 [ASSUMPTION, spec
	# 2026-07-01 §4B] — top up to max_stamina so the affordable-path assertions below are
	# actually exercising "affordable," not accidentally exercising the poverty case.
	c.resource_pool.stamina = c.resource_pool.max_stamina
	var starting_stamina: int = c.resource_pool.stamina

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"quake_slam"), "stageable at level 3, affordable, no CD")

	var before_count: int = c.turn_reels.size()
	plan.toggle_extra_ability(&"quake_slam")
	_check(plan.staged_extra_ability_id == &"quake_slam", "toggle stages quake_slam")

	# Preview should show the extra reel WITHOUT committing/spending anything yet.
	var previewed: Array[ActionReel] = plan.preview_reels()
	_check(previewed.size() == before_count + 1, "preview shows the loadout grown by 1 reel")
	_check(c.turn_reels.size() == before_count, "preview does not mutate turn_reels")
	_check(c.resource_pool.stamina == starting_stamina, "preview does not spend stamina")

	plan.commit()
	_check(c.turn_reels.size() == before_count + 1, "commit grows turn_reels by 1")
	var added: ActionReel = c.turn_reels[c.turn_reels.size() - 1]
	_check(added.is_weapon_attack, "the new reel is a real weapon-attack reel (joins paylines)")

	var found_hit_face: bool = false
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			found_hit_face = true
			_check(f.rider_effect_id == &"slow", "SUCCESS face carries the slow rider")
			_check(f.multiplier > 0.0, "SUCCESS face keeps real damage")
	_check(found_hit_face, "sanity: at least one SUCCESS face exists to check")

	var def: AbilityDef = c.find_extra_ability(&"quake_slam")
	_check(c.resource_pool.stamina == starting_stamina - def.cost, "commit spent the ability's stamina cost")

	# Cap check: fill the loadout to reel_cap, then staging must be refused even though affordable.
	var cap_c: Combatant = cc.build_combatant(true)
	cap_c.level = 3
	var cap_plan: MainPhasePlan = MainPhasePlan.new(cap_c)
	while cap_c.turn_reels.size() < cap_plan.reel_cap:
		cap_c.turn_reels.append(ActionReel.make_default(cap_c.weapon_type()))
	_check(not cap_plan.can_stage_extra_ability(&"quake_slam"), "not stageable when turn_reels is already at reel_cap")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 3
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"quake_slam"), "not stageable with 0 stamina")

	# Direct Combatant-method checks (mirrors try_sundering_strike's contract).
	var direct_c: Combatant = cc.build_combatant(true)
	var direct_before: int = direct_c.turn_reels.size()
	_check(direct_c.try_quake_slam(direct_c.weapon_type(), 3, 5), "try_quake_slam succeeds when affordable and under cap")
	_check(direct_c.turn_reels.size() == direct_before + 1, "try_quake_slam appended a reel")
	_check(not direct_c.try_quake_slam(direct_c.weapon_type(), 999, 5), "try_quake_slam fails when unaffordable")
	_check(not direct_c.try_quake_slam(direct_c.weapon_type(), 0, direct_c.turn_reels.size()), "try_quake_slam fails when already at cap")

	quit()
