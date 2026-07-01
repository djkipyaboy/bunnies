extends SceneTree

## Seer L5 "Hex" (spec 2026-07-01, task 26): a reel-adding extra ability, the SIXTH of its kind and
## the FIRST to spend MANA (the Seer's rail) rather than Stamina, and the first to attach a BENEFICIAL-
## capable DoT rider path's sibling — Hex splices a real-Mystic-damage weapon-attack reel whose hit
## faces carry the &"cursed" rider (a Mystic DAMAGE_OVER_TIME debuff, EffectLibrary Task 7). The actual
## DoT tick (and its beneficial-vs-harmful branching in combat.gd _apply_dot) is orchestrator-level
## (needs a running Combat scene + _panels) and is covered separately (test_dot_beneficial.gd) — this
## test covers the level gate, mana affordability, cap, and the reel/rider shape combat.gd depends on,
## plus REEL_ADDING_EXTRA_IDS membership.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

var _failures: int = 0
func _check_f(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"seer")
	var c: Combatant = cc.build_combatant(true)
	# Seer starts with 15 mana; Hex costs 4 — plenty for the affordability path under test.

	# Membership in the shared reel-adding guard list.
	_check_f(&"hex" in MainPhasePlan.REEL_ADDING_EXTRA_IDS, "hex is in REEL_ADDING_EXTRA_IDS")

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check_f(not early_plan.can_stage_extra_ability(&"hex"), "not stageable below level 5")
	c.level = 5

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check_f(plan.can_stage_extra_ability(&"hex"), "stageable at level 5, affordable, no CD")

	var before_count: int = c.turn_reels.size()
	var before_mana: int = c.resource_pool.mana
	plan.toggle_extra_ability(&"hex")
	_check_f(plan.staged_extra_ability_id == &"hex", "toggle stages hex")

	# Preview should show the extra reel WITHOUT committing/spending anything yet.
	var previewed: Array[ActionReel] = plan.preview_reels()
	_check_f(previewed.size() == before_count + 1, "preview shows the loadout grown by 1 reel")
	_check_f(c.turn_reels.size() == before_count, "preview does not mutate turn_reels")
	_check_f(c.resource_pool.mana == before_mana, "preview does not spend mana")

	var previewed_reel: ActionReel = previewed[previewed.size() - 1]
	_check_f(previewed_reel.is_weapon_attack, "previewed reel is a real weapon-attack reel (joins paylines)")

	plan.commit()
	_check_f(c.turn_reels.size() == before_count + 1, "commit grows turn_reels by 1")
	var added: ActionReel = c.turn_reels[c.turn_reels.size() - 1]
	_check_f(added.is_weapon_attack, "the new reel is a real weapon-attack reel (real damage, unlike Rend)")

	var found_hit_face: bool = false
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			found_hit_face = true
			_check_f(f.rider_effect_id == &"cursed", "SUCCESS face carries the cursed rider")
			_check_f(f.multiplier > 0.0, "SUCCESS face keeps real damage")
	_check_f(found_hit_face, "sanity: at least one SUCCESS face exists to check")

	var def: AbilityDef = c.find_extra_ability(&"hex")
	_check_f(def != null, "sanity: hex AbilityDef is registered on the Seer")
	_check_f(def.resource == &"mana", "hex is a mana-cost ability")
	_check_f(c.resource_pool.mana == before_mana - def.cost, "commit spent the ability's mana cost")

	# Cap check: fill the loadout to reel_cap, then staging must be refused even though affordable.
	var cap_c: Combatant = cc.build_combatant(true)
	cap_c.level = 5
	var cap_plan: MainPhasePlan = MainPhasePlan.new(cap_c)
	while cap_c.turn_reels.size() < cap_plan.reel_cap:
		cap_c.turn_reels.append(ActionReel.make_default(cap_c.weapon_type()))
	_check_f(not cap_plan.can_stage_extra_ability(&"hex"), "not stageable when turn_reels is already at reel_cap")

	# Affordability check: drain mana to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 5
	poor_c.resource_pool.mana = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check_f(not poor_plan.can_stage_extra_ability(&"hex"), "not stageable with 0 mana")

	# Direct Combatant-method checks (mirrors try_sundering_strike's contract; spends MANA).
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.mana = 10
	var direct_before: int = direct_c.turn_reels.size()
	var direct_before_mana: int = direct_c.resource_pool.mana
	_check_f(direct_c.try_hex(direct_c.weapon_type(), 4, 5), "try_hex succeeds when affordable and under cap")
	_check_f(direct_c.turn_reels.size() == direct_before + 1, "try_hex appended a reel")
	_check_f(direct_c.resource_pool.mana == direct_before_mana - 4, "try_hex spent 4 mana (not stamina)")
	var direct_added: ActionReel = direct_c.turn_reels[direct_c.turn_reels.size() - 1]
	_check_f(direct_added.is_weapon_attack, "try_hex's appended reel is a real weapon-attack reel")
	var direct_rider_ok: bool = false
	for f: ReelFace in direct_added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS and f.rider_effect_id == &"cursed":
			direct_rider_ok = true
	_check_f(direct_rider_ok, "try_hex's appended reel carries the cursed rider on its hit faces")
	_check_f(not direct_c.try_hex(direct_c.weapon_type(), 999, 5), "try_hex fails when unaffordable (mana)")
	_check_f(not direct_c.try_hex(direct_c.weapon_type(), 0, direct_c.turn_reels.size()), "try_hex fails when already at cap")

	print(("HEX TEST PASSED" if _failures == 0 else "HEX TEST FAILED: %d" % _failures))
	quit(_failures)
