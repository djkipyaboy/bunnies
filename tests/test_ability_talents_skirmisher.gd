extends SceneTree

# Headless test: the Skirmisher's 18 Ability Talent options (Task 17) — one row of 3 mutually-
# exclusive picks per Skirmisher ability (Flurry / Feint & Riposte / Quickstep / Riposte Storm /
# Opportunist / Sticky Wild). Exercises AbilityTalentLibrary.options_for(&"skirmisher", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# reel-instance-scoped flurry_deeper option (mirrors Task 16's slam_deeper/rampage_deeper precedent).
#
# Charging Opportunist's ACTUAL on-hit Bonus Meter charge lives in combat.gd's _apply_attack() —
# orchestrator-level, requires a running Combat scene — and is NOT headlessly tested here, consistent
# with this codebase's own documented precedent (tests/test_ability_talents_warrior.gd's header
# comment on Bleeding Wild). This test instead proves the precondition state combat.gd's wiring reads.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_skirmisher.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_skirmisher() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = 20
	c.begin_turn()  # populates turn_reels from the 4-reel Slashing Twin Daggers
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"flurry_deeper", &"flurry_hastening", &"flurry_efficient",
		&"feint_deeper", &"feint_lasting", &"feint_efficient",
		&"step_deeper", &"step_evasive", &"step_efficient",
		&"storm_deeper", &"storm_lasting", &"storm_swift",
		&"opportunist_deeper", &"opportunist_wider", &"opportunist_charging",
		&"sticky_deeper", &"sticky_hastening", &"sticky_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"skirmisher", row)
		_check(opts.size() == 3, "Skirmisher row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&skirmisher, ...)" % id)

func _test_flurry_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cost_delta(&"flurry") == 0, "no Flurry cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"flurry_efficient"), "picks flurry_efficient")
	_check(c.ability_talent_cost_delta(&"flurry") == -1, "flurry_efficient: Flurry costs 1 less Stamina")

	var c2: Combatant = _mk_skirmisher()
	_check(c2.pick_ability_talent(&"base_ability", &"flurry_deeper"), "picks flurry_deeper")
	_check(c2.try_splice_reel(c2.weapon_type(), c2.weapon_effective_base_damage(), 2, 5), "casts Flurry (deeper)")
	var reel: ActionReel = c2.turn_reels[c2.turn_reels.size() - 1]
	var checked_success: bool = false
	var checked_crit: bool = false
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face.multiplier, 1.10), "flurry_deeper: SUCCESS face multiplier is 1.10 (got %.3f)" % face.multiplier)
			checked_success = true
		elif face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			_check(is_equal_approx(face.multiplier, 2.20), "flurry_deeper: CRIT_SUCCESS face multiplier is 2.20 (got %.3f)" % face.multiplier)
			checked_crit = true
	_check(checked_success and checked_crit, "sanity: both hit tiers exist on the spliced reel to check")
	_check(reel.is_weapon_attack, "sanity: Flurry's added reel stays a weapon-attack reel (payline-eligible)")

	var c3: Combatant = _mk_skirmisher()
	_check(c3.try_splice_reel(c3.weapon_type(), c3.weapon_effective_base_damage(), 2, 5), "casts Flurry (baseline)")
	var reel3: ActionReel = c3.turn_reels[c3.turn_reels.size() - 1]
	for face3: ReelFace in reel3.faces:
		if face3.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face3.multiplier, 1.0), "baseline Flurry: SUCCESS multiplier stays 1.0 (got %.3f)" % face3.multiplier)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"base_ability", &"flurry_hastening"), "picks flurry_hastening")
	_check(c4.try_splice_reel(c4.weapon_type(), c4.weapon_effective_base_damage(), 2, 5), "casts Flurry (hastening)")
	var haste: Effect = c4._find_effect(&"haste")
	_check(haste != null, "flurry_hastening: Haste attached")
	_check(haste.duration == 1, "flurry_hastening: Haste lasts 1 turn (got %d)" % haste.duration)

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_skirmisher()
	_check(c5.pick_ability_talent(&"base_ability", &"flurry_efficient"), "first pick on the Flurry row succeeds")
	_check(not c5.pick_ability_talent(&"base_ability", &"flurry_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c5.has_ability_talent(&"flurry_efficient"), "the row's original pick is still active")

func _test_feint_riposte_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cost_delta(&"feint_riposte") == 0, "no Feint & Riposte cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"feint_efficient"), "picks feint_efficient")
	_check(c.ability_talent_cost_delta(&"feint_riposte") == -1, "feint_efficient: Feint & Riposte costs 1 less Stamina")

	var c2: Combatant = _mk_skirmisher()
	_check(c2.apply_feint_riposte(3), "casts Feint & Riposte (baseline)")
	var e: Effect = c2._find_effect(&"evasion")
	var t: Effect = c2._find_effect(&"taunt")
	_check(e != null and e.duration == 3, "baseline Feint & Riposte: Evasion lasts 3 turns (got %s)" % (str(e.duration) if e != null else "null"))
	_check(t != null and t.duration == 3, "baseline Feint & Riposte: Taunt lasts 3 turns (got %s)" % (str(t.duration) if t != null else "null"))
	_check(c2.riposte_charges == 0, "baseline Feint & Riposte grants no immediate riposte charge")

	var c3: Combatant = _mk_skirmisher()
	_check(c3.pick_ability_talent(&"ability_l2", &"feint_lasting"), "picks feint_lasting")
	_check(c3.apply_feint_riposte(3), "casts Feint & Riposte (lasting)")
	var e3: Effect = c3._find_effect(&"evasion")
	var t3: Effect = c3._find_effect(&"taunt")
	_check(e3.duration == 4, "feint_lasting: Evasion lasts 4 turns (got %d)" % e3.duration)
	_check(t3.duration == 4, "feint_lasting: Taunt lasts 4 turns too (got %d)" % t3.duration)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"ability_l2", &"feint_deeper"), "picks feint_deeper")
	_check(c4.riposte_charges == 0, "sanity: no riposte charges before casting")
	_check(c4.apply_feint_riposte(3), "casts Feint & Riposte (deeper)")
	_check(c4.riposte_charges == 1, "feint_deeper: grants +1 riposte charge immediately (got %d)" % c4.riposte_charges)

func _test_quickstep_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cost_delta(&"quickstep") == 0, "no Quickstep cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"step_efficient"), "picks step_efficient")
	_check(c.ability_talent_cost_delta(&"quickstep") == -1, "step_efficient: Quickstep costs 1 less Stamina")

	var c2: Combatant = _mk_skirmisher()
	_check(c2.apply_quickstep(3), "casts Quickstep (baseline)")
	var h: Effect = c2._find_effect(&"haste")
	_check(is_equal_approx(h.magnitude, 20.0), "baseline Quickstep: Haste magnitude is +20 Initiative (got %.1f)" % h.magnitude)
	_check(not c2.has_effect(&"evasion"), "baseline Quickstep grants no Evasion")

	var c3: Combatant = _mk_skirmisher()
	_check(c3.pick_ability_talent(&"ability_l3", &"step_deeper"), "picks step_deeper")
	_check(c3.apply_quickstep(3), "casts Quickstep (deeper)")
	var h3: Effect = c3._find_effect(&"haste")
	_check(is_equal_approx(h3.magnitude, 30.0), "step_deeper: Haste magnitude is +30 Initiative (got %.1f)" % h3.magnitude)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"ability_l3", &"step_evasive"), "picks step_evasive")
	_check(c4.apply_quickstep(3), "casts Quickstep (evasive)")
	var e4: Effect = c4._find_effect(&"evasion")
	_check(e4 != null, "step_evasive: Evasion attached")
	_check(e4.duration == 1, "step_evasive: Evasion lasts 1 turn (got %d)" % e4.duration)

func _test_riposte_storm_row() -> void:
	var c: Combatant = _mk_skirmisher()
	_check(c.ability_talent_cooldown_delta(&"riposte_storm") == 0, "no Riposte Storm cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"storm_swift"), "picks storm_swift")
	_check(c.ability_talent_cooldown_delta(&"riposte_storm") == -1, "storm_swift: Riposte Storm cooldown is 1 less turn")

	var c2: Combatant = _mk_skirmisher()
	c2.riposte_charges = 4
	_check(c2.fire_riposte_storm(4), "fires Riposte Storm (baseline, 4 charges)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp.magnitude, 1.60), "baseline Riposte Storm: 1.0 + 0.15*4 = 1.60 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 1, "baseline Riposte Storm: Empowered lasts 1 turn (got %d)" % emp.duration)
	_check(c2.riposte_charges == 0, "sanity: charges reset to 0 after firing")

	var c3: Combatant = _mk_skirmisher()
	c3.riposte_charges = 4
	_check(c3.pick_ability_talent(&"ability_l4", &"storm_deeper"), "picks storm_deeper")
	_check(c3.fire_riposte_storm(4), "fires Riposte Storm (deeper, 4 charges)")
	var emp3: Effect = c3._find_effect(&"empowered")
	_check(is_equal_approx(emp3.magnitude, 1.80), "storm_deeper: 1.0 + 0.20*4 = 1.80 (got %.3f)" % emp3.magnitude)

	var c4: Combatant = _mk_skirmisher()
	_check(c4.pick_ability_talent(&"ability_l4", &"storm_lasting"), "picks storm_lasting")
	_check(c4.fire_riposte_storm(4), "fires Riposte Storm (lasting)")
	var emp4: Effect = c4._find_effect(&"empowered")
	_check(emp4.duration == 2, "storm_lasting: Empowered lasts 2 turns (got %d)" % emp4.duration)

func _test_opportunist_row() -> void:
	var c: Combatant = _mk_skirmisher()
	c.passive_ability_id = &"opportunist"
	var slowed: Combatant = _mk_skirmisher()
	slowed.attach_effect(EffectLibrary.make(&"slow"))
	_check(is_equal_approx(c.passive_outgoing_multiplier(slowed), 1.15), "baseline Opportunist: +15% vs a Slowed defender")

	var c2: Combatant = _mk_skirmisher()
	c2.passive_ability_id = &"opportunist"
	_check(c2.pick_ability_talent(&"passive", &"opportunist_deeper"), "picks opportunist_deeper")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(slowed), 1.25), "opportunist_deeper: +25%% vs a Slowed defender (got %.3f)" % c2.passive_outgoing_multiplier(slowed))

	var c3: Combatant = _mk_skirmisher()
	c3.passive_ability_id = &"opportunist"
	var weakened: Combatant = _mk_skirmisher()
	weakened.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened), 1.0), "sanity: baseline Opportunist does NOT trigger vs a merely-Weakened defender")
	_check(c3.pick_ability_talent(&"passive", &"opportunist_wider"), "picks opportunist_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened), 1.15), "opportunist_wider: now also triggers vs a Weakened defender (got %.3f)" % c3.passive_outgoing_multiplier(weakened))

	# Charging Opportunist's ACTUAL on-hit meter charge lives in combat.gd's _apply_attack() — see
	# the file header comment above. This proves the precondition state combat.gd's wiring reads:
	# the pick itself, and that passive_outgoing_multiplier(defender) > 1.0 is genuinely readable as
	# "did Opportunist just trigger" for that check to use.
	var c4: Combatant = _mk_skirmisher()
	c4.passive_ability_id = &"opportunist"
	_check(c4.pick_ability_talent(&"passive", &"opportunist_charging"), "picks opportunist_charging")
	_check(c4.has_ability_talent(&"opportunist_charging"), "has_ability_talent sees opportunist_charging")
	_check(c4.passive_outgoing_multiplier(slowed) > 1.0, "opportunist_charging precondition: passive_outgoing_multiplier(defender) > 1.0 vs a Slowed defender")

func _test_sticky_wild_row() -> void:
	var c: Combatant = _mk_skirmisher()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_sticky_wild(c.weapon.reels.size(), 2), "fires Sticky Wild (baseline)")
	_check(not c.has_effect(&"empowered"), "baseline Sticky Wild grants no Empowered")
	_check(not c.has_effect(&"haste"), "baseline Sticky Wild grants no Haste")

	var c2: Combatant = _mk_skirmisher()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"sticky_deeper"), "picks sticky_deeper")
	_check(c2.fire_sticky_wild(c2.weapon.reels.size(), 2), "fires Sticky Wild (deeper)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(emp != null, "sticky_deeper: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.15), "sticky_deeper: Empowered is x1.15 (got %.3f)" % emp.magnitude)
	_check(emp.duration == 2, "sticky_deeper: Empowered lasts the same 2 spins as the wild itself (got %d)" % emp.duration)

	var c3: Combatant = _mk_skirmisher()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"sticky_hastening"), "picks sticky_hastening")
	_check(c3.fire_sticky_wild(c3.weapon.reels.size(), 2), "fires Sticky Wild (hastening)")
	var haste: Effect = c3._find_effect(&"haste")
	_check(haste != null, "sticky_hastening: Haste attached")
	_check(haste.duration == 2, "sticky_hastening: Haste lasts the same 2 spins as the wild itself (got %d)" % haste.duration)

	var c4: Combatant = _mk_skirmisher()
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"sticky_wild", "sanity: Skirmisher's Ultimate id is &sticky_wild")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Sticky Wild ultimate stages when the meter is armed")
	plan.commit()
	_check(c4.sticky_wild_spins_remaining == 2, "without Lasting Sticky Wild, firing it grants 2 spins (got %d)" % c4.sticky_wild_spins_remaining)

	var c5: Combatant = _mk_skirmisher()
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"sticky_lasting"), "picks sticky_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.sticky_wild_spins_remaining == 3, "sticky_lasting: firing Sticky Wild grants 3 spins (got %d)" % c5.sticky_wild_spins_remaining)

func _init() -> void:
	_test_options_for_shape()
	_test_flurry_row()
	_test_feint_riposte_row()
	_test_quickstep_row()
	_test_riposte_storm_row()
	_test_opportunist_row()
	_test_sticky_wild_row()
	print(("SKIRMISHER ABILITY TALENTS TEST PASSED" if _failures == 0 else "SKIRMISHER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
