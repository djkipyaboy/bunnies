extends SceneTree

## Ranger L7 "Snare Trap" (task 24): a reel-adding extra ability that splices one real-damage
## weapon-type (Piercing) reel whose hit faces also carry the &"rooted" rider — unlike Rend, which
## deals no direct damage. Also exercises the shared REEL_ADDING_EXTRA_IDS plumbing (cap-check +
## preview + commit) it extends alongside sundering_strike/quake_slam/jinx_the_odds.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

## Snare Trap costs 4 Stamina but the Ranger's start_stamina is only 3, so top each fresh combatant's
## rail up to a comfortable, known amount before the affordability assertions (mirrors the reference
## test's intent — it just happened Warrior's start_stamina == Sundering Strike's cost).
const START_STAMINA: int = 10

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"ranger")
	var c: Combatant = cc.build_combatant(true)
	c.resource_pool.stamina = START_STAMINA
	c.level = 7

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"snare_trap"), "not stageable below level 7")
	c.level = 7

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"snare_trap"), "stageable at level 7, affordable, no CD")

	var before_count: int = c.turn_reels.size()
	plan.toggle_extra_ability(&"snare_trap")
	_check(plan.staged_extra_ability_id == &"snare_trap", "toggle stages snare_trap")

	# Preview should show the extra reel WITHOUT committing/spending anything yet.
	var previewed: Array[ActionReel] = plan.preview_reels()
	_check(previewed.size() == before_count + 1, "preview shows the loadout grown by 1 reel")
	_check(c.turn_reels.size() == before_count, "preview does not mutate turn_reels")
	_check(c.resource_pool.stamina == START_STAMINA, "preview does not spend stamina")

	plan.commit()
	_check(c.turn_reels.size() == before_count + 1, "commit grows turn_reels by 1")
	var added: ActionReel = c.turn_reels[c.turn_reels.size() - 1]
	_check(added.is_weapon_attack, "the new reel is a real weapon-attack reel (joins paylines, unlike Rend)")

	var found_hit_face: bool = false
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			found_hit_face = true
			_check(f.rider_effect_id == &"rooted", "SUCCESS face carries the rooted rider")
			_check(f.multiplier > 0.0, "SUCCESS face keeps real damage (unlike Rend)")
	_check(found_hit_face, "sanity: at least one SUCCESS face exists to check")

	_check(c.resource_pool.stamina == START_STAMINA - 4, "commit spent the ability's stamina cost (4)")

	# Cap check: fill the loadout to reel_cap, then staging must be refused even though affordable.
	var cap_c: Combatant = cc.build_combatant(true)
	cap_c.resource_pool.stamina = START_STAMINA
	cap_c.level = 7
	var cap_plan: MainPhasePlan = MainPhasePlan.new(cap_c)
	while cap_c.turn_reels.size() < cap_plan.reel_cap:
		cap_c.turn_reels.append(ActionReel.make_default(cap_c.weapon_type()))
	_check(not cap_plan.can_stage_extra_ability(&"snare_trap"), "not stageable when turn_reels is already at reel_cap")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 7
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"snare_trap"), "not stageable with 0 stamina")

	# Direct Combatant-method checks (mirrors try_sundering_strike's contract).
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.stamina = START_STAMINA
	var direct_before: int = direct_c.turn_reels.size()
	_check(direct_c.try_snare_trap(direct_c.weapon_type(), 4, 5), "try_snare_trap succeeds when affordable and under cap")
	_check(direct_c.turn_reels.size() == direct_before + 1, "try_snare_trap appended a reel")
	_check(not direct_c.try_snare_trap(direct_c.weapon_type(), 999, 5), "try_snare_trap fails when unaffordable")
	_check(not direct_c.try_snare_trap(direct_c.weapon_type(), 0, direct_c.turn_reels.size()), "try_snare_trap fails when already at cap")

	quit()
