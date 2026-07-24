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
		&"rend_deeper_cut", &"rend_lasting_wound", &"rend_efficient",
		&"sunder_deeper", &"sunder_lingering", &"sunder_efficient",
		&"guard_reinforced", &"guard_cleansing", &"guard_lasting",
		&"wind_deeper", &"wind_empowering", &"wind_swift",
		&"stand_deeper", &"stand_wider", &"stand_guarded",
		&"wild_truer", &"wild_bleeding", &"wild_lasting",
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
	var c: Combatant = _mk_warrior()
	_check(c.ability_talent_cost_delta(&"rend") == 0, "no Rend cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"rend_efficient"), "picks rend_efficient")
	_check(c.has_ability_talent(&"rend_efficient"), "has_ability_talent sees rend_efficient")
	_check(c.ability_talent_cost_delta(&"rend") == -1, "rend_efficient: Rend costs 1 less Stamina")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "picks rend_deeper_cut")
	var bleed: Effect = EffectLibrary.make(&"bleed")
	var base_fractions: Array = bleed.dot_fractions.duplicate()
	c2.apply_rider_talent_adjustments(&"bleed", bleed, c2)
	for i: int in range(base_fractions.size()):
		_check(is_equal_approx(bleed.dot_fractions[i], base_fractions[i] * 1.25),
			"rend_deeper_cut: Bleed fraction %d is +25%% (got %.4f, want %.4f)" % [i, bleed.dot_fractions[i], base_fractions[i] * 1.25])
	_check(bleed.max_stacks == 3, "rend_deeper_cut alone leaves max_stacks at 3")

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"base_ability", &"rend_lasting_wound"), "picks rend_lasting_wound")
	var bleed2: Effect = EffectLibrary.make(&"bleed")
	c3.apply_rider_talent_adjustments(&"bleed", bleed2, c3)
	_check(bleed2.max_stacks == 4, "rend_lasting_wound: Bleed max_stacks is 4 (got %d)" % bleed2.max_stacks)
	_check(bleed2.dot_fractions.size() == 4, "rend_lasting_wound: Bleed gained a 4th stack fraction (got %d entries)" % bleed2.dot_fractions.size())
	_check(is_equal_approx(bleed2.dot_fractions[3], 1.55), "rend_lasting_wound: 4th stack fraction is 1.55 (got %.4f)" % bleed2.dot_fractions[3])

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"base_ability", &"rend_efficient"), "first pick on the Rend row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"rend_deeper_cut"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"rend_efficient"), "the row's original pick is still active")

func _test_sundering_strike_row() -> void:
	var c: Combatant = _mk_warrior()
	_check(c.ability_talent_cost_delta(&"sundering_strike") == 0, "no Sundering Strike cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"sunder_efficient"), "picks sunder_efficient")
	_check(c.ability_talent_cost_delta(&"sundering_strike") == -1, "sunder_efficient: Sundering Strike costs 1 less Stamina")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l2", &"sunder_deeper"), "picks sunder_deeper")
	var sundered: Effect = EffectLibrary.make(&"sundered")
	c2.apply_rider_talent_adjustments(&"sundered", sundered, c2)
	_check(is_equal_approx(sundered.magnitude, 1.35), "sunder_deeper: Sundered's incoming multiplier is 1.35 (got %.3f)" % sundered.magnitude)
	_check(sundered.duration == 2, "sunder_deeper alone leaves duration at 2")

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l2", &"sunder_lingering"), "picks sunder_lingering")
	var sundered2: Effect = EffectLibrary.make(&"sundered")
	c3.apply_rider_talent_adjustments(&"sundered", sundered2, c3)
	_check(sundered2.duration == 3, "sunder_lingering: Sundered lasts 3 turns (got %d)" % sundered2.duration)
	_check(is_equal_approx(sundered2.magnitude, 1.25), "sunder_lingering alone leaves magnitude at 1.25")

func _test_heroic_guard_row() -> void:
	var c: Combatant = _mk_warrior()
	_check(c.apply_heroic_guard(2), "casts Heroic Guard (baseline)")
	var g: Effect = c._find_effect(&"guarded")
	_check(g != null, "sanity: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.75), "baseline Heroic Guard: Guarded magnitude 0.75")
	_check(g.duration == 3, "baseline Heroic Guard: 3-turn duration")

	var c2: Combatant = _mk_warrior()
	_check(c2.pick_ability_talent(&"ability_l3", &"guard_reinforced"), "picks guard_reinforced")
	_check(c2.apply_heroic_guard(2), "casts Heroic Guard (reinforced)")
	var g2: Effect = c2._find_effect(&"guarded")
	_check(is_equal_approx(g2.magnitude, 0.65), "guard_reinforced: Guarded magnitude 0.65 (got %.3f)" % g2.magnitude)

	var c3: Combatant = _mk_warrior()
	_check(c3.pick_ability_talent(&"ability_l3", &"guard_lasting"), "picks guard_lasting")
	_check(c3.apply_heroic_guard(2), "casts Heroic Guard (lasting)")
	var g3: Effect = c3._find_effect(&"guarded")
	var t3: Effect = c3._find_effect(&"taunt")
	_check(g3.duration == 4, "guard_lasting: Guarded lasts 4 turns (got %d)" % g3.duration)
	_check(t3.duration == 4, "guard_lasting: Taunt lasts 4 turns too (got %d)" % t3.duration)

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l3", &"guard_cleansing"), "picks guard_cleansing")
	var slow: Effect = EffectLibrary.make(&"slow")
	c4.attach_effect(slow)
	_check(c4.has_effect(&"slow"), "sanity: a debuff is active before casting")
	_check(c4.apply_heroic_guard(2), "casts Heroic Guard (cleansing)")
	_check(not c4.has_effect(&"slow"), "guard_cleansing: the active debuff is cleansed on cast")
	_check(c4.has_effect(&"guarded"), "guard_cleansing still grants Guarded")

func _test_second_wind_row() -> void:
	var c: Combatant = _mk_warrior()
	_check(c.ability_talent_cooldown_delta(&"second_wind") == 0, "no Second Wind cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"wind_swift"), "picks wind_swift")
	_check(c.ability_talent_cooldown_delta(&"second_wind") == -1, "wind_swift: Second Wind cooldown is 1 less turn")

	var c2: Combatant = _mk_warrior()
	c2.max_hp = 100; c2.hp = 10
	_check(c2.pick_ability_talent(&"ability_l4", &"wind_deeper"), "picks wind_deeper")
	_check(c2.apply_second_wind(2), "casts Second Wind (deeper)")
	_check(c2.hp == 50, "wind_deeper: Second Wind heals 40%% max HP (10 + 40 = 50, got %d)" % c2.hp)

	var c3: Combatant = _mk_warrior()
	c3.max_hp = 100; c3.hp = 10
	_check(c3.apply_second_wind(2), "casts Second Wind (baseline)")
	_check(c3.hp == 40, "baseline Second Wind heals 30%% max HP (10 + 30 = 40, got %d)" % c3.hp)

	var c4: Combatant = _mk_warrior()
	_check(c4.pick_ability_talent(&"ability_l4", &"wind_empowering"), "picks wind_empowering")
	_check(c4.apply_second_wind(2), "casts Second Wind (empowering)")
	var emp: Effect = c4._find_effect(&"empowered")
	_check(emp != null, "wind_empowering: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.15), "wind_empowering: Empowered is x1.15 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 1, "wind_empowering: Empowered lasts 1 turn (got %d)" % emp.duration)

func _test_last_stand_row() -> void:
	var c: Combatant = _mk_warrior()
	c.passive_ability_id = &"last_stand"
	c.max_hp = 100; c.hp = 30
	_check(is_equal_approx(c.passive_outgoing_multiplier(), 1.2), "baseline Last Stand: +20% at 30% HP")

	var c2: Combatant = _mk_warrior()
	c2.passive_ability_id = &"last_stand"
	c2.max_hp = 100; c2.hp = 30
	_check(c2.pick_ability_talent(&"passive", &"stand_deeper"), "picks stand_deeper")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(), 1.3), "stand_deeper: +30%% at 30%% HP (got %.3f)" % c2.passive_outgoing_multiplier())

	var c3: Combatant = _mk_warrior()
	c3.passive_ability_id = &"last_stand"
	c3.max_hp = 100; c3.hp = 35
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "sanity: 35% HP is above the baseline 30% threshold")
	_check(c3.pick_ability_talent(&"passive", &"stand_wider"), "picks stand_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.2), "stand_wider: Last Stand now active at 35% HP too (widened to 40%)")
	c3.hp = 41
	_check(is_equal_approx(c3.passive_outgoing_multiplier(), 1.0), "stand_wider: still inactive just above the widened 40% threshold")

	var c4: Combatant = _mk_warrior()
	c4.passive_ability_id = &"last_stand"
	c4.max_hp = 100; c4.hp = 30
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "baseline Last Stand grants no incoming reduction")
	_check(c4.pick_ability_talent(&"passive", &"stand_guarded"), "picks stand_guarded")
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 0.9), "stand_guarded: -10%% incoming while Last Stand is active (got %.3f)" % c4.passive_incoming_multiplier())
	c4.hp = 31
	_check(is_equal_approx(c4.passive_incoming_multiplier(), 1.0), "stand_guarded: no reduction once Last Stand's own condition drops off")

func _test_wild_row() -> void:
	var c: Combatant = _mk_warrior()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 1), "fires Wild (baseline)")
	_check(not c.has_effect(&"empowered"), "baseline Wild grants no Empowered")

	var c2: Combatant = _mk_warrior()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"wild_truer"), "picks wild_truer")
	_check(c2.fire_sticky_wild(c2.weapon.reels.size(), 1), "fires Wild (truer)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(emp != null, "wild_truer: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.15), "wild_truer: Empowered is x1.15 (got %.3f)" % emp.magnitude)

	# Bleeding Wild's precondition state (the actual on-hit attach lives in combat.gd's
	# _apply_attack(), orchestrator-level — see the file header comment above).
	var c3: Combatant = _mk_warrior()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"wild_bleeding"), "picks wild_bleeding")
	_check(c3.fire_sticky_wild(c3.weapon.reels.size(), 1), "fires Wild (bleeding)")
	_check(c3.sticky_wild_spins_remaining > 0, "Wild is active for combat.gd's wild_bleeding check to read")

	var c4: Combatant = _mk_warrior()
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"wild", "sanity: Warrior's Ultimate id is &wild")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Wild ultimate stages when the meter is armed")
	plan.commit()
	_check(c4.sticky_wild_spins_remaining == 1, "without Lasting Wild, firing Wild grants 1 spin (got %d)" % c4.sticky_wild_spins_remaining)

	var c5: Combatant = _mk_warrior()
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"wild_lasting"), "picks wild_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.sticky_wild_spins_remaining == 2, "wild_lasting: firing Wild grants 2 spins (got %d)" % c5.sticky_wild_spins_remaining)

func _init() -> void:
	_test_options_for_shape()
	_test_rend_row()
	_test_sundering_strike_row()
	_test_heroic_guard_row()
	_test_second_wind_row()
	_test_last_stand_row()
	_test_wild_row()
	print(("WARRIOR ABILITY TALENTS TEST PASSED" if _failures == 0 else "WARRIOR ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
