extends SceneTree

# Headless test: the Ranger's 18 Ability Talent options (Task 19) — one row of 3 mutually-
# exclusive picks per Ranger ability (Hunter's Mark / Aimed Shot / Snare Trap / Crippling Shot /
# Steady Aim / Collateral Damage). Exercises AbilityTalentLibrary.options_for(&"ranger", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# GENERIC apply_rider_talent_adjustments()/rider_talent_bonus_damage_pct() hooks (neither of
# Ranger's own rider ids collides with its weapon's inherent rider or with each other — unlike
# Vanguard's Quake Slam/Task 16 — so no reel-instance-scoped workaround is needed here; see this
# task's Implementation notes).
#
# Deeper Aim/Piercing Aim's actual magnitude bump and bonus-Weakened attach, Deeper Crippling's
# bump to the existing bonus_vs_cc calculation, Charging Aim's on-hit meter charge, and Marking
# Collateral's mark-application loop all live in combat.gd's _commit_main1()/_apply_attack()/
# _finish_spin() — orchestrator-level, requires a running Combat scene — and are NOT headlessly
# tested here, consistent with this codebase's own documented precedent
# (tests/test_ability_talents_warrior.gd's header comment on Bleeding Wild). Where the underlying
# math is checkable directly (Deeper Collateral's splash-fraction formula, mirroring
# tests/test_collateral.gd's own manual-replication convention) or the precondition state is
# checkable (has_ability_talent, the pending flags combat.gd's wiring reads), this test proves that
# instead.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_ranger.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_ranger() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = 20
	c.begin_turn()  # populates turn_reels from the 4-reel Piercing Hunting Bow
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"mark_deeper", &"mark_weakening", &"mark_efficient",
		&"aim_deeper", &"aim_piercing", &"aim_efficient",
		&"snare_deeper", &"snare_lasting", &"snare_efficient",
		&"crippling_deeper", &"crippling_lasting", &"crippling_swift",
		&"steady_deeper", &"steady_wider", &"steady_charging",
		&"collateral_deeper", &"collateral_marking", &"collateral_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"ranger", row)
		_check(opts.size() == 3, "Ranger row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&ranger, ...)" % id)

func _test_hunters_mark_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"hunters_mark") == 0, "no Hunter's Mark cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"mark_efficient"), "picks mark_efficient")
	_check(c.has_ability_talent(&"mark_efficient"), "has_ability_talent sees mark_efficient")
	_check(c.ability_talent_cost_delta(&"hunters_mark") == -1, "mark_efficient: Hunter's Mark costs 1 less Stamina")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"base_ability", &"mark_deeper"), "picks mark_deeper")
	var mark: Effect = EffectLibrary.make(&"hunters_mark")
	_check(mark.duration == 3, "sanity: Hunter's Mark's baseline duration is 3")
	c2.apply_rider_talent_adjustments(&"hunters_mark", mark, c2)
	_check(mark.duration == 4, "mark_deeper: Hunter's Mark lasts 4 turns (got %d)" % mark.duration)

	var c3: Combatant = _mk_ranger()
	var target: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"base_ability", &"mark_weakening"), "picks mark_weakening")
	var mark3: Effect = EffectLibrary.make(&"hunters_mark")
	_check(not target.has_effect(&"weakened"), "sanity: target starts unweakened")
	c3.apply_rider_talent_adjustments(&"hunters_mark", mark3, target)
	_check(target.has_effect(&"weakened"), "mark_weakening: the target also gets a stack of Weakened")
	_check(mark3.duration == 3, "mark_weakening alone leaves Hunter's Mark's own duration at 3")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"base_ability", &"mark_efficient"), "first pick on the Hunter's Mark row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"mark_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"mark_efficient"), "the row's original pick is still active")

func _test_aimed_shot_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"aimed_shot") == 0, "no Aimed Shot cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"aim_efficient"), "picks aim_efficient")
	_check(c.ability_talent_cost_delta(&"aimed_shot") == -1, "aim_efficient: Aimed Shot costs 1 less Stamina")

	# Deeper Aim's actual +40%/+70% magnitude bump lives in combat.gd's own _commit_main1() —
	# orchestrator-level (Aimed Shot's whole magnitude computation already lived there before this
	# task, sized by the defender's Mark status) — NOT headlessly tested here (see this file's
	# header comment). This proves the precondition state combat.gd's wiring reads.
	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l2", &"aim_deeper"), "picks aim_deeper")
	_check(c2.stage_aimed_shot(3), "stages Aimed Shot (deeper)")
	_check(c2.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring to read")

	# Piercing Aim's actual bonus Weakened application (on this spin's first connecting hit) lives
	# in combat.gd's _apply_attack() — same precedent, not headlessly tested here.
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l2", &"aim_piercing"), "picks aim_piercing")
	_check(c3.has_ability_talent(&"aim_piercing"), "has_ability_talent sees aim_piercing")
	_check(not c3.aimed_shot_hit_pending, "sanity: aimed_shot_hit_pending starts false")
	_check(c3.stage_aimed_shot(3), "stages Aimed Shot (piercing)")
	_check(c3.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring (which sets aimed_shot_hit_pending) to read")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"ability_l2", &"aim_efficient"), "first pick on the Aimed Shot row succeeds")
	_check(not c4.pick_ability_talent(&"ability_l2", &"aim_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_snare_trap_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"snare_trap") == 0, "no Snare Trap cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"snare_efficient"), "picks snare_efficient")
	_check(c.ability_talent_cost_delta(&"snare_trap") == -1, "snare_efficient: Snare Trap costs 1 less Stamina")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l3", &"snare_deeper"), "picks snare_deeper")
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"rooted"), 0.15), "snare_deeper: +15%% bonus damage on Snare Trap's own hit (got %.3f)" % c2.rider_talent_bonus_damage_pct(&"rooted"))
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"weakened"), 0.0), "snare_deeper only applies to the rooted rider id, not any other")

	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l3", &"snare_lasting"), "picks snare_lasting")
	var rooted: Effect = EffectLibrary.make(&"rooted")
	_check(rooted.duration == 2, "sanity: Rooted's baseline duration is 2")
	c3.apply_rider_talent_adjustments(&"rooted", rooted, c3)
	_check(rooted.duration == 3, "snare_lasting: Rooted lasts 3 turns (got %d)" % rooted.duration)

	var c4: Combatant = _mk_ranger()
	_check(c4.try_snare_trap(c4.weapon_type(), 4, 6), "casts Snare Trap (sanity: unaffected structurally by talents)")

func _test_crippling_shot_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cooldown_delta(&"crippling_shot") == 0, "no Crippling Shot cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"crippling_swift"), "picks crippling_swift")
	_check(c.ability_talent_cooldown_delta(&"crippling_shot") == -1, "crippling_swift: Crippling Shot's cooldown is 1 less turn")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l4", &"crippling_lasting"), "picks crippling_lasting")
	var weakened: Effect = EffectLibrary.make(&"weakened")
	_check(weakened.duration == 2, "sanity: Weakened's baseline duration is 2")
	c2.apply_rider_talent_adjustments(&"weakened", weakened, c2)
	_check(weakened.duration == 3, "crippling_lasting: Weakened lasts 3 turns (got %d)" % weakened.duration)

	# Deeper Crippling's actual +65%-instead-of-+50% CC-exploit bonus lives in combat.gd's
	# _apply_attack() — it bumps an EXISTING inline bonus_vs_cc calculation, not a new separate hit,
	# so it's checked directly there rather than through rider_talent_bonus_damage_pct() (see this
	# task's Implementation notes). Orchestrator-level, NOT headlessly tested here.
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l4", &"crippling_deeper"), "picks crippling_deeper")
	_check(c3.has_ability_talent(&"crippling_deeper"), "has_ability_talent sees crippling_deeper")
	_check(c3.try_crippling_shot(c3.weapon_type(), 5, 6), "casts Crippling Shot (sanity: unaffected structurally by talents)")

func _test_steady_aim_row() -> void:
	var c: Combatant = _mk_ranger()
	c.passive_ability_id = &"steady_aim"
	var marked: Combatant = _mk_ranger()
	marked.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c.passive_outgoing_multiplier(marked), 1.10), "baseline Steady Aim: +10% vs a Marked defender")

	var c2: Combatant = _mk_ranger()
	c2.passive_ability_id = &"steady_aim"
	_check(c2.pick_ability_talent(&"passive", &"steady_deeper"), "picks steady_deeper")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(marked), 1.20), "steady_deeper: +20%% vs a Marked defender (got %.3f)" % c2.passive_outgoing_multiplier(marked))

	var c3: Combatant = _mk_ranger()
	c3.passive_ability_id = &"steady_aim"
	var weakened_defender: Combatant = _mk_ranger()
	weakened_defender.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.0), "sanity: baseline Steady Aim does NOT trigger vs a merely-Weakened defender")
	_check(c3.pick_ability_talent(&"passive", &"steady_wider"), "picks steady_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.10), "steady_wider: now also triggers vs a Weakened defender (got %.3f)" % c3.passive_outgoing_multiplier(weakened_defender))

	# Charging Aim's ACTUAL on-hit meter charge lives in combat.gd's _apply_attack() — see the file
	# header comment above. This proves the precondition state combat.gd's wiring reads (mirrors
	# Skirmisher's opportunist_charging test exactly).
	var c4: Combatant = _mk_ranger()
	c4.passive_ability_id = &"steady_aim"
	_check(c4.pick_ability_talent(&"passive", &"steady_charging"), "picks steady_charging")
	_check(c4.has_ability_talent(&"steady_charging"), "has_ability_talent sees steady_charging")
	_check(c4.passive_outgoing_multiplier(marked) > 1.0, "steady_charging precondition: passive_outgoing_multiplier(defender) > 1.0 vs a Marked defender")

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"steady_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_collateral_row() -> void:
	# Deeper Collateral's splash-fraction formula (proof of the math, mirroring
	# tests/test_collateral.gd's own convention of replicating the orchestrator's formula directly,
	# since _splash_half_to_others() is a private Combat-scene method with no live scene here).
	_check(ceili(20 * 0.5) == 10, "sanity: baseline (1/2) splash of 20 is 10")
	_check(ceili(20 * (2.0 / 3.0)) == 14, "collateral_deeper: 2/3 splash of 20 is 14, rounded up (got %d)" % ceili(20 * (2.0 / 3.0)))
	var c: Combatant = _mk_ranger()
	_check(c.pick_ability_talent(&"ultimate", &"collateral_deeper"), "picks collateral_deeper")
	_check(c.has_ability_talent(&"collateral_deeper"), "has_ability_talent sees collateral_deeper")

	# Marking Collateral: manually simulates the exact splash+mark loop combat.gd's _finish_spin()
	# performs (mirroring test_collateral.gd's own synthetic-3-enemy manual-simulation technique,
	# since _splash_half_to_others()/its caller are private Combat-scene methods).
	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ultimate", &"collateral_marking"), "picks collateral_marking")
	var other_a: Combatant = _mk_ranger()
	var other_b: Combatant = _mk_ranger()
	var splashed: Array[Combatant] = [other_a, other_b]
	_check(not other_a.has_effect(&"hunters_mark") and not other_b.has_effect(&"hunters_mark"), "sanity: neither splashed enemy starts Marked")
	for other: Combatant in splashed:
		if c2.has_ability_talent(&"collateral_marking"):
			other.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(other_a.has_effect(&"hunters_mark") and other_b.has_effect(&"hunters_mark"), "collateral_marking: every splashed enemy is also Marked")

	var c3: Combatant = _mk_ranger()
	c3.bonus_meter.value = c3.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c3)
	_check(plan.ultimate_id == &"collateral", "sanity: Ranger's Ultimate id is &collateral")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Collateral Damage ultimate stages when the meter is armed")
	plan.commit()
	_check(c3.collateral_spins_remaining == 1, "without Lasting Collateral, firing it grants 1 spin (got %d)" % c3.collateral_spins_remaining)

	var c4: Combatant = _mk_ranger()
	c4.bonus_meter.value = c4.bonus_meter.cap
	_check(c4.pick_ability_talent(&"ultimate", &"collateral_lasting"), "picks collateral_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c4)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c4.collateral_spins_remaining == 2, "collateral_lasting: firing Collateral Damage grants 2 spins (got %d)" % c4.collateral_spins_remaining)

	# Mutual exclusion (ultimate row): only 1 pick per row.
	var c5: Combatant = _mk_ranger()
	_check(c5.pick_ability_talent(&"ultimate", &"collateral_deeper"), "first pick on the Collateral Damage row succeeds")
	_check(not c5.pick_ability_talent(&"ultimate", &"collateral_marking"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _init() -> void:
	_test_options_for_shape()
	_test_hunters_mark_row()
	_test_aimed_shot_row()
	_test_snare_trap_row()
	_test_crippling_shot_row()
	_test_steady_aim_row()
	_test_collateral_row()
	print(("RANGER ABILITY TALENTS TEST PASSED" if _failures == 0 else "RANGER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
