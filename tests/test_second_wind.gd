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

	# Rank-2 (2026-09-06 warrior-rank2-content spec §5): heal 30%% -> 40%%, plus a new 2-turn HoT
	# at 5%% max HP per turn (10%% total). ability_l4 ranks to 2 at level 8.
	var rank2_c: Combatant = cc.build_combatant(true)
	rank2_c.level = 8
	rank2_c.resource_pool.stamina = rank2_c.resource_pool.max_stamina
	rank2_c.max_hp = 100; rank2_c.hp = 10
	_check(rank2_c.apply_second_wind(5), "apply_second_wind succeeds at rank 2")
	_check(rank2_c.hp == 50, "rank 2 baseline: heals 40%% max HP (10 + 40 = 50, got %d)" % rank2_c.hp)
	var hot: Effect = rank2_c._find_effect(&"second_wind_hot")
	_check(hot != null, "rank 2: a second_wind_hot HoT is attached")
	_check(hot != null and hot.duration == 2, "rank 2 baseline: HoT lasts 2 turns (got %d)" % (hot.duration if hot != null else -1))
	_check(hot != null and hot.beneficial, "the HoT is beneficial (heals, doesn't damage)")
	_check(hot != null and is_equal_approx(hot.dot_base_damage, 100.0), "the HoT's dot_base_damage is max_hp (got %.1f)" % (hot.dot_base_damage if hot != null else -1.0))
	_check(hot != null and hot.dot_fractions == [0.05], "the HoT ticks a flat 5%% every turn (got %s)" % str(hot.dot_fractions if hot != null else []))

	# Rank 2 + wind_deeper: heal 40%% + 10 = 50%%, HoT extends to 3 turns (same 5%%/turn rate, 15%% total).
	var rank2_deeper_c: Combatant = cc.build_combatant(true)
	rank2_deeper_c.level = 8
	rank2_deeper_c.resource_pool.stamina = rank2_deeper_c.resource_pool.max_stamina
	rank2_deeper_c.max_hp = 100; rank2_deeper_c.hp = 10
	_check(rank2_deeper_c.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(rank2_deeper_c.apply_second_wind(5), "apply_second_wind succeeds at rank 2 + wind_deeper")
	_check(rank2_deeper_c.hp == 60, "rank 2 + wind_deeper: heals 50%% max HP (10 + 50 = 60, got %d)" % rank2_deeper_c.hp)
	var hot_deeper: Effect = rank2_deeper_c._find_effect(&"second_wind_hot")
	_check(hot_deeper != null and hot_deeper.duration == 3, "rank 2 + wind_deeper: HoT lasts 3 turns (got %d)" % (hot_deeper.duration if hot_deeper != null else -1))

	# Rank<2 regression: no HoT, heal stays at the old 30%%.
	var rank1_c: Combatant = cc.build_combatant(true)
	rank1_c.level = 4
	rank1_c.resource_pool.stamina = rank1_c.resource_pool.max_stamina
	rank1_c.max_hp = 100; rank1_c.hp = 10
	_check(rank1_c.apply_second_wind(5), "apply_second_wind succeeds at rank<2")
	_check(rank1_c.hp == 40, "rank<2: still heals 30%% max HP (10 + 30 = 40, got %d)" % rank1_c.hp)
	_check(rank1_c._find_effect(&"second_wind_hot") == null, "rank<2: no HoT attached")

	quit()
