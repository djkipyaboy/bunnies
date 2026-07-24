extends SceneTree

## Warden L2 "Entangle" (spec docs/superpowers/specs — task 29): a reel-adding extra ability, the
## SEVENTH and FINAL member of REEL_ADDING_EXTRA_IDS. Splices a real-Earth-damage weapon-attack reel
## whose hit faces carry the &"rooted" rider — the SAME shared rider Ranger's Snare Trap (task 24)
## uses, just spent from the Warden's Mana rail instead of Ranger's Stamina. Mirrors test_hex.gd's
## shape (mana-based reel-adding extra ability) and test_snare_trap.gd's rider (&"rooted").

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

var _failures: int = 0
func _check_f(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"warden")
	var c: Combatant = cc.build_combatant(true)
	# Warden starts with 12 mana; Entangle costs 4 — plenty for the affordability path under test.

	# Membership in the shared reel-adding guard list.
	_check_f(&"entangle" in MainPhasePlan.REEL_ADDING_EXTRA_IDS, "entangle is in REEL_ADDING_EXTRA_IDS")

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check_f(not early_plan.can_stage_extra_ability(&"entangle"), "not stageable below level 2")
	c.level = 2

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check_f(plan.can_stage_extra_ability(&"entangle"), "stageable at level 2, affordable, no CD")

	var before_count: int = c.turn_reels.size()
	var before_mana: int = c.resource_pool.mana
	plan.toggle_extra_ability(&"entangle")
	_check_f(plan.staged_extra_ability_id == &"entangle", "toggle stages entangle")

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
	_check_f(added.is_weapon_attack, "the new reel is a real weapon-attack reel (real damage, unlike Rallying Cry)")

	var found_hit_face: bool = false
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			found_hit_face = true
			_check_f(f.rider_effect_id == &"rooted", "SUCCESS face carries the rooted rider")
			_check_f(f.multiplier > 0.0, "SUCCESS face keeps real damage")
	_check_f(found_hit_face, "sanity: at least one SUCCESS face exists to check")

	var def: AbilityDef = c.find_extra_ability(&"entangle")
	_check_f(def != null, "sanity: entangle AbilityDef is registered on the Warden")
	_check_f(def.resource == &"mana", "entangle is a mana-cost ability")
	_check_f(c.resource_pool.mana == before_mana - def.cost, "commit spent the ability's mana cost")

	# Cap check: fill the loadout to reel_cap, then staging must be refused even though affordable.
	var cap_c: Combatant = cc.build_combatant(true)
	cap_c.level = 2
	var cap_plan: MainPhasePlan = MainPhasePlan.new(cap_c)
	while cap_c.turn_reels.size() < cap_plan.reel_cap:
		cap_c.turn_reels.append(ActionReel.make_default(cap_c.weapon_type()))
	_check_f(not cap_plan.can_stage_extra_ability(&"entangle"), "not stageable when turn_reels is already at reel_cap")

	# Affordability check: drain mana to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 2
	poor_c.resource_pool.mana = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check_f(not poor_plan.can_stage_extra_ability(&"entangle"), "not stageable with 0 mana")

	# Direct Combatant-method checks (mirrors try_hex's contract; spends MANA).
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.mana = 10
	var direct_before: int = direct_c.turn_reels.size()
	var direct_before_mana: int = direct_c.resource_pool.mana
	_check_f(direct_c.try_entangle(direct_c.weapon_type(), 4, 5), "try_entangle succeeds when affordable and under cap")
	_check_f(direct_c.turn_reels.size() == direct_before + 1, "try_entangle appended a reel")
	_check_f(direct_c.resource_pool.mana == direct_before_mana - 4, "try_entangle spent 4 mana (not stamina)")
	var direct_added: ActionReel = direct_c.turn_reels[direct_c.turn_reels.size() - 1]
	_check_f(direct_added.is_weapon_attack, "try_entangle's appended reel is a real weapon-attack reel")
	var direct_rider_ok: bool = false
	for f: ReelFace in direct_added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS and f.rider_effect_id == &"rooted":
			direct_rider_ok = true
	_check_f(direct_rider_ok, "try_entangle's appended reel carries the rooted rider on its hit faces")
	_check_f(not direct_c.try_entangle(direct_c.weapon_type(), 999, 5), "try_entangle fails when unaffordable (mana)")
	_check_f(not direct_c.try_entangle(direct_c.weapon_type(), 0, direct_c.turn_reels.size()), "try_entangle fails when already at cap")

	print(("ENTANGLE TEST PASSED" if _failures == 0 else "ENTANGLE TEST FAILED: %d" % _failures))
	quit(_failures)
