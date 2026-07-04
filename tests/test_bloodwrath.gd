extends SceneTree

## Vanguard L5 "Bloodwrath" (spec 2026-07-01 §4B, task 14): a self-cast, NO-reel extra ability that
## grants Empowered scaled to the caster's missing-HP% (+1% dmg per 1% HP missing, capped +50% —
## steepened from +1%/2%, cap 40%, on playtest 2026-07-04 so the scaling is felt sooner) — a
## high-risk juggernaut buff. Like Heroic Guard (task 12) this only exercises the shared commit()
## dispatch; it does NOT touch REEL_ADDING_EXTRA_IDS/preview_reels.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _empowered_magnitude(c: Combatant) -> float:
	for e: Effect in c.active_effects:
		if e.id == &"empowered":
			return e.magnitude
	return -1.0

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"vanguard")
	var c: Combatant = cc.build_combatant(true)

	# Below unlock level: not stageable even though everything else is fine.
	c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(not early_plan.can_stage_extra_ability(&"bloodwrath"), "not stageable below level 5")

	c.level = 5
	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"bloodwrath"), "stageable at level 5, affordable, no CD")

	plan.toggle_extra_ability(&"bloodwrath")
	_check(plan.staged_extra_ability_id == &"bloodwrath", "toggle stages bloodwrath")

	var before_reel_count: int = c.turn_reels.size()
	var before_stamina: int = c.resource_pool.stamina

	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff, unlike Sundering Strike)")
	_check(c.has_effect(&"empowered"), "commit attaches Empowered")
	_check(c.resource_pool.stamina == before_stamina - 3, "commit spent the ability's stamina cost (3)")
	# c is at full HP (0% missing) — magnitude should be the floor, 1.0, not the EffectLibrary default (1.4).
	_check(is_equal_approx(_empowered_magnitude(c), 1.0), "commit's Empowered magnitude is 1.0 at full HP (0% missing)")

	# Affordability check: drain stamina to 0, staging must be refused.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.level = 5
	poor_c.resource_pool.stamina = 0
	var poor_plan: MainPhasePlan = MainPhasePlan.new(poor_c)
	_check(not poor_plan.can_stage_extra_ability(&"bloodwrath"), "not stageable with 0 stamina")

	# Direct Combatant-method checks: full HP -> floor magnitude (1.0).
	var direct_c: Combatant = cc.build_combatant(true)
	var direct_before_stamina: int = direct_c.resource_pool.stamina
	_check(direct_c.apply_bloodwrath(3), "apply_bloodwrath succeeds when affordable")
	_check(direct_c.has_effect(&"empowered"), "apply_bloodwrath attached Empowered")
	_check(direct_c.resource_pool.stamina == direct_before_stamina - 3, "apply_bloodwrath spent stamina")
	_check(is_equal_approx(_empowered_magnitude(direct_c), 1.0), "apply_bloodwrath magnitude is 1.0 at full HP (0% missing)")
	_check(not direct_c.apply_bloodwrath(999), "apply_bloodwrath fails when unaffordable")

	# Near-death Combatant-method check: hp == 1 on Vanguard's large max_hp (base_max_hp 300 + Vigor 5
	# from base_stats, applied by build_combatant()'s apply_stats()) -> ~99.7% missing, magnitude
	# capped at 1.50 (raised from 1.40 on 2026-07-04). Use the live derived max_hp rather than
	# hardcoding 300 so this test tracks the class data (mirrors test_second_wind.gd's pattern).
	var dying_c: Combatant = cc.build_combatant(true)
	dying_c.hp = 1
	_check(dying_c.apply_bloodwrath(3), "apply_bloodwrath succeeds while near death")
	_check(is_equal_approx(_empowered_magnitude(dying_c), 1.50), "apply_bloodwrath magnitude caps at 1.50 (~99.7%% missing HP)")

	# Formula shared by the caster path and the Abilities-menu live tooltip (must never drift).
	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.0), 0.0), "bloodwrath_bonus_pct(0% missing) == 0%")
	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.25), 0.25), "bloodwrath_bonus_pct(25% missing) == 25% (1%-per-1%)")
	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.90), 0.50), "bloodwrath_bonus_pct(90% missing) caps at 50%")

	quit()
