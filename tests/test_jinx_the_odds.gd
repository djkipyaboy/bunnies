extends SceneTree

## Chancer L7 "Jinx the Odds" (spec 2026-07-01 §4, task 21): a reel-adding extra ability that
## splices one real-damage weapon-type reel whose hit faces also carry the &"jinxed" rider —
## mirrors Warrior's Sundering Strike (Task 11) and Vanguard's Quake Slam (Task 15) exactly,
## exercising the shared REEL_ADDING_EXTRA_IDS plumbing (cap-check + preview + commit).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"chancer")
	var c: Combatant = cc.build_combatant(true)
	c.level = 7

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"jinx_the_odds"), "not stageable below level 7")
	c.level = 7

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"jinx_the_odds"), "stageable at level 7, affordable, no CD")

	var before_count: int = c.turn_reels.size()
	plan.toggle_extra_ability(&"jinx_the_odds")
	_check(plan.staged_extra_ability_id == &"jinx_the_odds", "toggle stages jinx_the_odds")

	# Preview should show the extra reel WITHOUT committing/spending anything yet.
	var previewed: Array[ActionReel] = plan.preview_reels()
	_check(previewed.size() == before_count + 1, "preview shows the loadout grown by 1 reel")
	_check(c.turn_reels.size() == before_count, "preview does not mutate turn_reels")
	_check(c.resource_pool.stamina == cc.start_stamina, "preview does not spend stamina")

	plan.commit()
	_check(c.turn_reels.size() == before_count + 1, "commit grows turn_reels by 1")
	var added: ActionReel = c.turn_reels[c.turn_reels.size() - 1]
	_check(added.is_weapon_attack, "the new reel is a real weapon-attack reel (joins paylines)")

	var found_hit_face: bool = false
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			found_hit_face = true
			_check(f.rider_effect_id == &"jinxed", "SUCCESS face carries the jinxed rider")
			_check(f.multiplier > 0.0, "SUCCESS face keeps real damage")
	_check(found_hit_face, "sanity: at least one SUCCESS face exists to check")

	_check(c.resource_pool.stamina == cc.start_stamina - 3, "commit spent the ability's stamina cost (3)")

	# Cap check: fill the loadout to reel_cap, then staging must be refused even though affordable.
	var cap_c: Combatant = cc.build_combatant(true)
	cap_c.level = 7
	var cap_plan: MainPhasePlan = MainPhasePlan.new(cap_c)
	while cap_c.turn_reels.size() < cap_plan.reel_cap:
		cap_c.turn_reels.append(ActionReel.make_default(cap_c.weapon_type()))
	_check(not cap_plan.can_stage_extra_ability(&"jinx_the_odds"), "not stageable when turn_reels is already at reel_cap")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 7
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"jinx_the_odds"), "not stageable with 0 stamina")

	# Direct Combatant-method checks (mirrors try_sundering_strike/try_quake_slam's contract).
	var direct_c: Combatant = cc.build_combatant(true)
	var direct_before: int = direct_c.turn_reels.size()
	_check(direct_c.try_jinx_the_odds(direct_c.weapon_type(), 3, 5), "try_jinx_the_odds succeeds when affordable and under cap")
	_check(direct_c.turn_reels.size() == direct_before + 1, "try_jinx_the_odds appended a reel")
	_check(not direct_c.try_jinx_the_odds(direct_c.weapon_type(), 999, 5), "try_jinx_the_odds fails when unaffordable")
	_check(not direct_c.try_jinx_the_odds(direct_c.weapon_type(), 0, direct_c.turn_reels.size()), "try_jinx_the_odds fails when already at cap")

	quit()
