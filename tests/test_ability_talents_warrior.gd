extends SceneTree

# Headless test: the Warrior's 18 Ability Talent options (Task 15) — one row of 3 mutually-
# exclusive picks per Warrior ability (Rend / Sundering Strike / Heroic Guard / Second Wind /
# Last Stand / Wild). Exercises AbilityTalentLibrary.options_for(&"warrior", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and
# apply_rider_talent_adjustments() for the Bleed/Sundered riders.
#
# Bleeding Wild's ACTUAL on-hit attach lives in combat.gd's _apply_attack() — orchestrator-level,
# requires a running Combat scene — and is NOT headlessly tested here, consistent with this
# codebase's own documented precedent (tests/test_crippling_shot.gd's header comment on its
# bonus_vs_cc check). This test instead proves the precondition state combat.gd's wiring reads.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warrior.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_warrior() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = 20
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"rend_deeper_cut", &"rend_lasting_wound", &"rend_salted_wound",
		&"sunder_deeper", &"sunder_vicious_return", &"sunder_twist_knife",
		&"guard_reinforced", &"guard_vengeful", &"guard_reckless",
		&"wind_deeper", &"wind_empowering", &"wind_desperate_recovery",
		&"stand_vengeful", &"stand_wider", &"stand_guarded",
		&"devastating_executioner", &"devastating_bleeding", &"devastating_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"warrior", row)
		_check(opts.size() == 3, "Warrior row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&warrior, ...)" % id)

func _test_rend_row() -> void:
	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "picks rend_deeper_cut")
	var bleed: Effect = EffectLibrary.make(&"bleed")
	c2.apply_rider_talent_adjustments(&"bleed", bleed, c2)
	var rank2_base: Array = [0.60, 0.95, 1.35, 1.70, 2.25]
	for i: int in range(rank2_base.size()):
		_check(is_equal_approx(bleed.dot_fractions[i], rank2_base[i] * 1.35),
			"rend_deeper_cut (rank 2): Bleed fraction %d is the rank-2 curve +35%% (got %.4f, want %.4f)" % [i, bleed.dot_fractions[i], rank2_base[i] * 1.35])
	_check(bleed.max_stacks == 4, "rend_deeper_cut alone (rank 2, no rend_lasting_wound): max_stacks is 4 (got %d)" % bleed.max_stacks)

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "picks rend_lasting_wound")
	var bleed2: Effect = EffectLibrary.make(&"bleed")
	c3.apply_rider_talent_adjustments(&"bleed", bleed2, c3)
	_check(bleed2.max_stacks == 5, "rend_lasting_wound (rank 2): Bleed max_stacks is 5 (got %d)" % bleed2.max_stacks)
	_check(bleed2.dot_fractions.size() == 5, "rend_lasting_wound (rank 2): Bleed curve has 5 entries (got %d)" % bleed2.dot_fractions.size())
	_check(is_equal_approx(bleed2.dot_fractions[4], 2.25), "rend_lasting_wound (rank 2): 5th stack fraction is the deliberate spike, 2.25 (got %.4f)" % bleed2.dot_fractions[4])

	# Salted Wound: bonus only fires if the TARGET already carries Sundered.
	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"base_ability", &"rend_salted_wound"), "picks rend_salted_wound")
	var target_plain: Combatant = _mk_warrior()
	var bleed3: Effect = EffectLibrary.make(&"bleed")
	c4.apply_rider_talent_adjustments(&"bleed", bleed3, target_plain)
	for i: int in range(rank2_base.size()):
		_check(is_equal_approx(bleed3.dot_fractions[i], rank2_base[i]),
			"rend_salted_wound (rank 2): no bonus vs. a target with no Sundered (fraction %d unchanged from the rank-2 curve)" % i)

	var c5: Combatant = _mk_warrior()
	_check(c5.pick_ability_talent(&"base_ability", &"rend_salted_wound"), "picks rend_salted_wound")
	var target_sundered: Combatant = _mk_warrior()
	target_sundered.attach_effect(EffectLibrary.make(&"sundered"))
	var bleed4: Effect = EffectLibrary.make(&"bleed")
	c5.apply_rider_talent_adjustments(&"bleed", bleed4, target_sundered)
	for i: int in range(rank2_base.size()):
		_check(is_equal_approx(bleed4.dot_fractions[i], rank2_base[i] * 1.25),
			"rend_salted_wound (rank 2): +25%% vs. a Sundered target (fraction %d got %.4f, want %.4f)" % [i, bleed4.dot_fractions[i], rank2_base[i] * 1.25])

	# Mutual exclusion: only 1 pick per row.
	var c6: Combatant = _mk_warrior()
	_check(c6.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "first pick on the Rend row succeeds")
	_check(not c6.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c6.has_ability_talent(&"rend_deeper_cut"), "the row's original pick is still active")

	# Rank<2 regression: below base_ability's rank-2/talent threshold (level 5), the OLD rank-1
	# curve/cap still apply (no talent can be picked this low, so this proves the untouched branch).
	var c7: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c7.level = 1
	var bleed5: Effect = EffectLibrary.make(&"bleed")
	var rank1_base: Array = bleed5.dot_fractions.duplicate()
	c7.apply_rider_talent_adjustments(&"bleed", bleed5, c7)
	_check(rank1_base == [0.50, 0.80, 1.15], "sanity: EffectLibrary's Bleed default is still the rank-1 curve")
	_check(bleed5.dot_fractions == rank1_base, "rank<2: Bleed curve is untouched at level 1")
	_check(bleed5.max_stacks == 3, "rank<2: Bleed max_stacks is untouched at 3 (got %d)" % bleed5.max_stacks)

func _test_sundering_strike_row() -> void:
	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "picks sunder_deeper")
	var sundered: Effect = EffectLibrary.make(&"sundered")
	c2.apply_rider_talent_adjustments(&"sundered", sundered, c2)
	_check(is_equal_approx(sundered.magnitude, 1.45), "sunder_deeper (rank 2): Sundered's incoming multiplier is 1.45 (got %.3f)" % sundered.magnitude)
	_check(sundered.duration == 2, "sunder_deeper alone leaves duration at 2")

	# Vicious Return / Twist the Knife: the actual on-hit refund/bonus-damage lives in combat.gd's
	# _apply_attack() (orchestrator-level), same documented precedent as Bleeding Wild (see this
	# file's header comment) — headlessly we only prove the talent is a real, pickable, mutually-
	# exclusive option on this row.
	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l2", &"sunder_vicious_return"), "picks sunder_vicious_return")
	_check(c3.has_ability_talent(&"sunder_vicious_return"), "has_ability_talent sees sunder_vicious_return")
	_check(not c3.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l2", &"sunder_twist_knife"), "picks sunder_twist_knife")
	_check(c4.has_ability_talent(&"sunder_twist_knife"), "has_ability_talent sees sunder_twist_knife")

	# Rank<2 regression + rank-2-no-talent baseline.
	var c7: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c7.level = 1
	var sundered2: Effect = EffectLibrary.make(&"sundered")
	c7.apply_rider_talent_adjustments(&"sundered", sundered2, c7)
	_check(is_equal_approx(sundered2.magnitude, 1.30), "rank<2: Sundered baseline magnitude untouched at 1.30 (got %.3f)" % sundered2.magnitude)

	var c8: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c8.level = 6  # ability_l2's rank-2 threshold, no talent picked
	var sundered3: Effect = EffectLibrary.make(&"sundered")
	c8.apply_rider_talent_adjustments(&"sundered", sundered3, c8)
	_check(is_equal_approx(sundered3.magnitude, 1.40), "rank 2 baseline (no talent): Sundered magnitude is 1.40 (got %.3f)" % sundered3.magnitude)

func _test_heroic_guard_row() -> void:
	var c: Combatant = _mk_warrior()
	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.apply_heroic_guard(2), "casts Heroic Guard (baseline)")
	var g: Effect = c._find_effect(&"guarded")
	var t: Effect = c._find_effect(&"taunt")
	_check(g != null, "sanity: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.70), "baseline Heroic Guard: Guarded magnitude 0.70 (got %.3f)" % g.magnitude)
	_check(g.duration == 4, "baseline Heroic Guard: 4-turn duration")
	_check(t != null and t.duration == 4, "baseline Heroic Guard: Taunt attached, 4-turn duration")
	_check(not c.has_effect(&"slow"), "baseline Heroic Guard now cleanses on cast unconditionally")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l3", &"guard_reinforced"), "picks guard_reinforced")
	_check(c2.apply_heroic_guard(2), "casts Heroic Guard (reinforced)")
	var g2: Effect = c2._find_effect(&"guarded")
	_check(is_equal_approx(g2.magnitude, 0.60), "guard_reinforced: Guarded magnitude 0.60 (got %.3f)" % g2.magnitude)

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l3", &"guard_reckless"), "picks guard_reckless")
	_check(c3.apply_heroic_guard(2, 5), "casts Heroic Guard (reckless)")
	_check(c3._find_effect(&"taunt") == null, "guard_reckless: no Taunt is applied")
	_check(c3._find_effect(&"guarded") != null, "guard_reckless: Guarded is still applied")
	# The bonus reel is no longer a one-off splice inside apply_heroic_guard() itself — it now
	# comes from a reel_surge Effect (matching Wheat's stage-3 idiom) that combat.gd's
	# _commit_main1() re-splices EVERY turn for its whole duration, unlike the old direct splice
	# which only ever fired once at cast time. Proving the Effect is attached with the right
	# duration is the correct headless signal here (same precedent as Vicious Return/Twist the
	# Knife above — the real per-turn splice lives in combat.gd, orchestrator-level).
	var surge_effect: Effect = c3._find_effect(&"reel_surge")
	_check(surge_effect != null and surge_effect.duration == 4, "guard_reckless: reel_surge effect attached with 4-turn duration")

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l3", &"guard_vengeful"), "picks guard_vengeful")
	_check(c4.apply_heroic_guard(2), "casts Heroic Guard (vengeful)")
	var enemy_plain: Combatant = _mk_warrior()
	var enemy_bled: Combatant = _mk_warrior()
	enemy_bled.attach_effect(EffectLibrary.make(&"bleed"))
	_check(is_equal_approx(c4.outgoing_damage_multiplier(enemy_plain), 1.0), "guard_vengeful: no bonus vs. an undebuffed target")
	_check(is_equal_approx(c4.outgoing_damage_multiplier(enemy_bled), 1.20), "guard_vengeful: +20%% vs. a Bled target while Guarded (got %.3f)" % c4.outgoing_damage_multiplier(enemy_bled))
	var enemy_sundered: Combatant = _mk_warrior()
	enemy_sundered.attach_effect(EffectLibrary.make(&"sundered"))
	_check(is_equal_approx(c4.outgoing_damage_multiplier(enemy_sundered), 1.20), "guard_vengeful: +20%% vs. a Sundered target while Guarded (the OR's other half, got %.3f)" % c4.outgoing_damage_multiplier(enemy_sundered))

	var c5: Combatant = _mk_warrior()
	_check(c5.pick_ability_talent(&"ability_l3", &"guard_vengeful"), "picks guard_vengeful")
	var enemy_bled2: Combatant = _mk_warrior()
	enemy_bled2.attach_effect(EffectLibrary.make(&"bleed"))
	_check(is_equal_approx(c5.outgoing_damage_multiplier(enemy_bled2), 1.0), "guard_vengeful: no bonus vs. a Bled target when NOT currently Guarded")

	# Mutual exclusion: only 1 pick per row.
	var c6: Combatant = _mk_warrior()
	_check(c6.pick_ability_talent(&"ability_l3", &"guard_reinforced"), "first pick on the Heroic Guard row succeeds")
	_check(not c6.pick_ability_talent(&"ability_l3", &"guard_reckless"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_second_wind_row() -> void:
	var c2: Combatant = _mk_warrior()
	c2.max_hp = 100; c2.hp = 10
	_check(c2.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(c2.apply_second_wind(2), "casts Second Wind (deeper, rank 2)")
	_check(c2.hp == 60, "wind_deeper (rank 2): Second Wind heals 50%% max HP (10 + 50 = 60, got %d)" % c2.hp)
	var hot2: Effect = c2._find_effect(&"second_wind_hot")
	_check(hot2 != null and hot2.duration == 3, "wind_deeper (rank 2): HoT lasts 3 turns (got %d)" % (hot2.duration if hot2 != null else -1))

	var c3: Combatant = _mk_warrior()
	c3.max_hp = 100; c3.hp = 10
	_check(c3.pick_ability_talent(&"ability_l4", &"wind_empowering"), "picks wind_empowering")
	_check(c3.apply_second_wind(2), "casts Second Wind (empowering)")
	var emp: Effect = c3._find_effect(&"empowered")
	_check(emp != null and emp.duration == 2, "wind_empowering: Empowered lasts 2 turns (got %d)" % (emp.duration if emp != null else -1))

	# Desperate Recovery: the cooldown discount only applies while at/below Last Stand's threshold
	# AT THE MOMENT OF CASTING (checked before this cast's own heal changes hp).
	var c4: Combatant = _mk_warrior()
	c4.max_hp = 100; c4.hp = 25
	_check(c4.pick_ability_talent(&"ability_l4", &"wind_desperate_recovery"), "picks wind_desperate_recovery")
	_check(c4.ability_talent_cooldown_delta(&"second_wind") == -2, "wind_desperate_recovery: -2 cooldown while at/below 30%% HP (got %d)" % c4.ability_talent_cooldown_delta(&"second_wind"))

	var c5: Combatant = _mk_warrior()
	c5.max_hp = 100; c5.hp = 50
	_check(c5.pick_ability_talent(&"ability_l4", &"wind_desperate_recovery"), "picks wind_desperate_recovery")
	_check(c5.ability_talent_cooldown_delta(&"second_wind") == 0, "wind_desperate_recovery: no discount above the threshold (got %d)" % c5.ability_talent_cooldown_delta(&"second_wind"))

	# wind_desperate_recovery (row ability_l4) + stand_wider (row passive) live on different rows,
	# so both CAN be picked on the same Combatant (unlike stand_guarded, which shares stand_wider's
	# row and can never coexist with it). At hp=35/100 — above the base 30% Last Stand threshold
	# but at/below stand_wider's widened 40% — Desperate Recovery must read the WIDENED threshold,
	# not the base one.
	var c5b: Combatant = _mk_warrior()
	c5b.max_hp = 100; c5b.hp = 35
	_check(c5b.pick_ability_talent(&"ability_l4", &"wind_desperate_recovery"), "picks wind_desperate_recovery (widened-threshold case)")
	_check(c5b.pick_ability_talent(&"passive", &"stand_wider"), "picks stand_wider (widened-threshold case)")
	_check(c5b.ability_talent_cooldown_delta(&"second_wind") == -2, "wind_desperate_recovery: -2 cooldown at 35%% HP when stand_wider widens the threshold to 40%% (got %d)" % c5b.ability_talent_cooldown_delta(&"second_wind"))

	# Mutual exclusion: only 1 pick per row.
	var c6: Combatant = _mk_warrior()
	_check(c6.pick_ability_talent(&"ability_l4", &"wind_deeper"), "first pick on the Second Wind row succeeds")
	_check(not c6.pick_ability_talent(&"ability_l4", &"wind_empowering"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_last_stand_row() -> void:
	var c: Combatant = _mk_warrior()
	c.passive_ability_id = &"last_stand"
	c.max_hp = 100; c.hp = 30
	_check(is_equal_approx(c.passive_outgoing_multiplier(), 1.34), "rank 2 (amplified): Last Stand is +34%% at 30%% HP")

	var c3: Combatant = _mk_warrior()
	c3.passive_ability_id = &"last_stand"
	c3.max_hp = 100; c3.hp = 35
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "sanity: 35%% HP is above the baseline 30%% threshold")
	_check(c3.pick_ability_talent(&"passive", &"stand_wider"), "picks stand_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.34), "stand_wider (rank 2): Last Stand now active at 35%% HP too (widened to 40%%), +34%%")
	c3.hp = 41
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "stand_wider: still inactive just above the widened 40%% threshold")

	var c4: Combatant = _mk_warrior()
	c4.passive_ability_id = &"last_stand"
	c4.max_hp = 100; c4.hp = 30
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "baseline Last Stand grants no incoming reduction")
	_check(c4.pick_ability_talent(&"passive", &"stand_guarded"), "picks stand_guarded")
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 0.9), "stand_guarded: -10%% incoming while Last Stand is active (got %.3f)" % c4.passive_incoming_multiplier())
	c4.hp = 31
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "stand_guarded: no reduction once Last Stand's own condition drops off")

	# Rank<2 regression: below the passive row's amplification threshold (level 9).
	var c9: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c9.level = 8  # >= 5 (passive active) but < 9 (still rank-1)
	c9.passive_ability_id = &"last_stand"
	c9.max_hp = 100; c9.hp = 30
	_check(is_equal_approx(c9.passive_outgoing_multiplier(), 1.24), "rank<2: Last Stand is still +24%% at 30%% HP (unamplified)")

func _test_devastating_strikes_row() -> void:
	var c: Combatant = _mk_warrior()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 1), "fires Devastating Strikes (baseline, direct low-level call)")
	_check(not c.has_effect(&"empowered"), "baseline Devastating Strikes grants no Empowered")

	var c2: Combatant = _mk_warrior()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"devastating_executioner"), "picks devastating_executioner")
	_check(c2.fire_sticky_wild(c2.weapon.reels.size(), 1), "fires Devastating Strikes (executioner)")
	var enemy_plain: Combatant = _mk_warrior()
	var enemy_doubly_debuffed: Combatant = _mk_warrior()
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"bleed"))
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"sundered"))
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_plain), 1.0), "devastating_executioner: no bonus vs. an undebuffed target")
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_doubly_debuffed), 1.25), "devastating_executioner: +25%% vs. a Bled+Sundered target while active (got %.3f)" % c2.outgoing_damage_multiplier(enemy_doubly_debuffed))
	c2.consume_wild_spin()
	_check(is_equal_approx(c2.outgoing_damage_multiplier(enemy_doubly_debuffed), 1.0), "devastating_executioner: no bonus once consumed")

	# Bleeding's precondition state (the actual on-hit attach lives in combat.gd's _apply_attack(),
	# orchestrator-level — see the file header comment above).
	var c3: Combatant = _mk_warrior()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"devastating_bleeding"), "picks devastating_bleeding")
	_check(c3.fire_sticky_wild(c3.weapon.reels.size(), 1), "fires Devastating Strikes (bleeding)")
	_check(c3.sticky_wild_spins_remaining > 0, "Devastating Strikes is active for combat.gd's devastating_bleeding check to read")

	# c4/c5 are level MAX (rank 2 for the ultimate row) via _mk_warrior(), so committing through the
	# real MainPhasePlan dispatch now exercises the rank-2 reel top-up (§7.1) for real.
	var c4: Combatant = _mk_warrior()
	c4.begin_turn()  # seeds turn_reels from the weapon (3 reels) — matches combat.gd's real turn order
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"devastating_strikes", "sanity: Warrior's Ultimate id is &devastating_strikes")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Devastating Strikes stages when the meter is armed")
	plan.commit()
	_check(c4.sticky_wild_spins_remaining == 1, "without Lasting Strikes, firing grants 1 spin (got %d)" % c4.sticky_wild_spins_remaining)
	_check(c4.turn_reels.size() == 5, "rank 2: reel top-up fills the loadout to 5 (got %d)" % c4.turn_reels.size())
	_check(c4.sticky_wild_count == 5, "rank 2: all 5 topped-up reels are marked wild (got %d)" % c4.sticky_wild_count)

	var c5: Combatant = _mk_warrior()
	c5.begin_turn()  # seeds turn_reels from the weapon (3 reels) — matches combat.gd's real turn order
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"devastating_lasting"), "picks devastating_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.sticky_wild_spins_remaining == 2, "devastating_lasting: firing grants 2 spins (got %d)" % c5.sticky_wild_spins_remaining)
	_check(c5.turn_reels.size() == 5, "rank 2 + devastating_lasting: reel top-up still fills to 5 (got %d)" % c5.turn_reels.size())

	# Rank<2 regression: a fresh level-1 Combatant (ultimate row's rank-2 threshold is level 10 —
	# MAX_LEVEL itself — so this can't be tested via _mk_warrior()).
	var c6: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	c6.begin_turn()  # seeds turn_reels from the weapon (3 reels) — matches combat.gd's real turn order
	c6.bonus_meter.value = c6.bonus_meter.cap
	var plan3: MainPhasePlan = MainPhasePlan.new(c6)
	plan3.toggle_ultimate()
	plan3.commit()
	_check(c6.turn_reels.size() == 3, "rank<2: no reel top-up, stays at the weapon baseline of 3 (got %d)" % c6.turn_reels.size())
	_check(c6.sticky_wild_count == 3, "rank<2: only the 3 baseline reels are marked wild (got %d)" % c6.sticky_wild_count)

func _init() -> void:
	_test_options_for_shape()
	_test_rend_row()
	_test_sundering_strike_row()
	_test_heroic_guard_row()
	_test_second_wind_row()
	_test_last_stand_row()
	_test_devastating_strikes_row()
	print(("WARRIOR ABILITY TALENTS TEST PASSED" if _failures == 0 else "WARRIOR ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
