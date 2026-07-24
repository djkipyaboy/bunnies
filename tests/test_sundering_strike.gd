extends SceneTree

## Warrior L2 "Sundering Strike" (spec 2026-07-01 §4B, task 11): a reel-adding extra ability that
## splices one real-damage weapon-type reel whose hit faces also carry the &"sundered" rider —
## unlike Rend, which deals no direct damage. Also exercises the shared REEL_ADDING_EXTRA_IDS
## plumbing (cap-check + preview + commit) that later reel-adding extra abilities will extend.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"warrior")
	var c: Combatant = cc.build_combatant(true)
	c.level = 2

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"sundering_strike"), "not stageable below level 2")
	c.level = 2

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"sundering_strike"), "stageable at level 2, affordable, no CD")

	var before_count: int = c.turn_reels.size()
	plan.toggle_extra_ability(&"sundering_strike")
	_check(plan.staged_extra_ability_id == &"sundering_strike", "toggle stages sundering_strike")

	# Preview should show the extra reel WITHOUT committing/spending anything yet.
	var previewed: Array[ActionReel] = plan.preview_reels()
	_check(previewed.size() == before_count + 1, "preview shows the loadout grown by 1 reel")
	_check(c.turn_reels.size() == before_count, "preview does not mutate turn_reels")
	_check(c.resource_pool.stamina == cc.start_stamina, "preview does not spend stamina")

	plan.commit()
	_check(c.turn_reels.size() == before_count + 1, "commit grows turn_reels by 1")
	var added: ActionReel = c.turn_reels[c.turn_reels.size() - 1]
	_check(added.is_weapon_attack, "the new reel is a real weapon-attack reel (joins paylines, unlike Rend)")

	var found_hit_face: bool = false
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			found_hit_face = true
			_check(f.rider_effect_id == &"sundered", "SUCCESS face carries the sundered rider")
			_check(f.multiplier > 0.0, "SUCCESS face keeps real damage (unlike Rend)")
	_check(found_hit_face, "sanity: at least one SUCCESS face exists to check")

	_check(c.resource_pool.stamina == cc.start_stamina - 3, "commit spent the ability's stamina cost (3)")

	# Cap check: fill the loadout to reel_cap, then staging must be refused even though affordable.
	var cap_c: Combatant = cc.build_combatant(true)
	cap_c.level = 2
	var cap_plan: MainPhasePlan = MainPhasePlan.new(cap_c)
	while cap_c.turn_reels.size() < cap_plan.reel_cap:
		cap_c.turn_reels.append(ActionReel.make_default(cap_c.weapon_type()))
	_check(not cap_plan.can_stage_extra_ability(&"sundering_strike"), "not stageable when turn_reels is already at reel_cap")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 2
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"sundering_strike"), "not stageable with 0 stamina")

	# Direct Combatant-method checks (mirrors try_rend_reel's contract).
	var direct_c: Combatant = cc.build_combatant(true)
	var direct_before: int = direct_c.turn_reels.size()
	_check(direct_c.try_sundering_strike(direct_c.weapon_type(), 3, 5), "try_sundering_strike succeeds when affordable and under cap")
	_check(direct_c.turn_reels.size() == direct_before + 1, "try_sundering_strike appended a reel")
	_check(not direct_c.try_sundering_strike(direct_c.weapon_type(), 999, 5), "try_sundering_strike fails when unaffordable")
	_check(not direct_c.try_sundering_strike(direct_c.weapon_type(), 0, direct_c.turn_reels.size()), "try_sundering_strike fails when already at cap")

	quit()
