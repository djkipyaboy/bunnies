extends SceneTree

## Ranger L4 "Crippling Shot" (spec 2026-07-01, task 25): a reel-adding extra ability, the FIFTH
## of its kind, and the FIRST to use ActionReel.make_rider_attack()'s optional bonus_vs_cc param
## and CombatResolver.AttackResult.source_reel. Splices a real-damage weapon-type reel whose hit
## faces carry the &"weakened" rider AND whose reel is flagged bonus_vs_cc — combat.gd's
## _apply_attack() reads that flag post-spin and deals +50% bonus damage if the target is already
## Slowed/Rooted/Stunned. That combat.gd bonus-damage check is orchestrator-level (reads live
## Combatant state mid-fight via _apply_attack, which requires a running Combat scene) and is NOT
## headlessly testable here — consistent with prior tasks' precedent (e.g. Task 22/23). This test
## covers the level gate, affordability, cap, and the reel/rider/flag shape that combat.gd depends on.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"ranger")
	var c: Combatant = cc.build_combatant(true)
	c.level = 4
	# Crippling Shot costs 5 stamina but the Ranger's start_stamina is only 3 (spec §3.4 — the pool
	# regens across turns); top up so the affordability path under test is the level/cap/CD gate, not
	# a starting-pool shortfall unrelated to this ability.
	c.resource_pool.stamina = 5

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"crippling_shot"), "not stageable below level 4")
	c.level = 4

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"crippling_shot"), "stageable at level 4, affordable, no CD")

	var before_count: int = c.turn_reels.size()
	plan.toggle_extra_ability(&"crippling_shot")
	_check(plan.staged_extra_ability_id == &"crippling_shot", "toggle stages crippling_shot")

	# Preview should show the extra reel WITHOUT committing/spending anything yet.
	var previewed: Array[ActionReel] = plan.preview_reels()
	_check(previewed.size() == before_count + 1, "preview shows the loadout grown by 1 reel")
	_check(c.turn_reels.size() == before_count, "preview does not mutate turn_reels")
	_check(c.resource_pool.stamina == 5, "preview does not spend stamina")

	var previewed_reel: ActionReel = previewed[previewed.size() - 1]
	_check(previewed_reel.is_weapon_attack, "previewed reel is a real weapon-attack reel (joins paylines)")
	_check(previewed_reel.bonus_vs_cc, "previewed reel is flagged bonus_vs_cc (combat.gd reads this post-spin)")

	plan.commit()
	_check(c.turn_reels.size() == before_count + 1, "commit grows turn_reels by 1")
	var added: ActionReel = c.turn_reels[c.turn_reels.size() - 1]
	_check(added.is_weapon_attack, "the new reel is a real weapon-attack reel (real damage, unlike Rend)")
	_check(added.bonus_vs_cc, "the committed reel carries bonus_vs_cc == true")

	var found_hit_face: bool = false
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			found_hit_face = true
			_check(f.rider_effect_id == &"weakened", "SUCCESS face carries the weakened rider")
			_check(f.multiplier > 0.0, "SUCCESS face keeps real damage")
	_check(found_hit_face, "sanity: at least one SUCCESS face exists to check")

	var def: AbilityDef = c.find_extra_ability(&"crippling_shot")
	_check(def != null, "sanity: crippling_shot AbilityDef is registered on the Ranger")
	_check(c.resource_pool.stamina == 5 - def.cost, "commit spent the ability's stamina cost")
	_check(def.cooldown_turns == 3, "crippling_shot has the spec'd 3-turn cooldown")
	_check(c.is_on_cooldown(&"crippling_shot"), "commit starts the cooldown")

	# Cap check: fill the loadout to reel_cap, then staging must be refused even though affordable.
	var cap_c: Combatant = cc.build_combatant(true)
	cap_c.level = 4
	cap_c.resource_pool.stamina = 5
	var cap_plan: MainPhasePlan = MainPhasePlan.new(cap_c)
	while cap_c.turn_reels.size() < cap_plan.reel_cap:
		cap_c.turn_reels.append(ActionReel.make_default(cap_c.weapon_type()))
	_check(not cap_plan.can_stage_extra_ability(&"crippling_shot"), "not stageable when turn_reels is already at reel_cap")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 4
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"crippling_shot"), "not stageable with 0 stamina")

	# Direct Combatant-method checks (mirrors try_snare_trap's contract).
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.stamina = 5
	var direct_before: int = direct_c.turn_reels.size()
	_check(direct_c.try_crippling_shot(direct_c.weapon_type(), 5, 5), "try_crippling_shot succeeds when affordable and under cap")
	_check(direct_c.turn_reels.size() == direct_before + 1, "try_crippling_shot appended a reel")
	var direct_added: ActionReel = direct_c.turn_reels[direct_c.turn_reels.size() - 1]
	_check(direct_added.bonus_vs_cc, "try_crippling_shot's appended reel carries bonus_vs_cc == true")
	_check(not direct_c.try_crippling_shot(direct_c.weapon_type(), 999, 5), "try_crippling_shot fails when unaffordable")
	_check(not direct_c.try_crippling_shot(direct_c.weapon_type(), 0, direct_c.turn_reels.size()), "try_crippling_shot fails when already at cap")

	quit()
