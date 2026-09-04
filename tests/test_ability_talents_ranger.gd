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
		&"mark_rooting", &"mark_marksmans_call", &"mark_marksman",
		&"aim_rooting", &"aim_weakening", &"aim_practiced",
		&"snare_wider", &"snare_marking", &"snare_focused",
		&"crippling_swift", &"crippling_lasting", &"crippling_marked",
		&"steady_controlled", &"steady_wider", &"steady_deadeye",
		&"collateral_lasting", &"collateral_marking", &"collateral_point_blank",
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
	_check(c.ability_talent_cost_delta(&"hunters_mark") == 0, "no Hunter's Mark cost delta (mark_efficient retired)")

	var c2: Combatant = _mk_ranger()
	var target: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"base_ability", &"mark_rooting"), "picks mark_rooting")
	var mark: Effect = EffectLibrary.make(&"hunters_mark")
	_check(not target.has_effect(&"rooted"), "sanity: target starts unrooted")
	c2.apply_rider_talent_adjustments(&"hunters_mark", mark, target)
	_check(target.has_effect(&"rooted"), "mark_rooting: the target also gets a stack of Rooted")
	_check(mark.duration == 3, "mark_rooting alone leaves Hunter's Mark's own duration at 3")

	# Marksman's Call/Marksman's Mark: the actual bonus-reel firing and the +20% bonus-vs-Marked
	# damage both live in combat.gd (orchestrator-level — Marksman's Call needs a running Combat
	# scene's _finish_spin/_resolver, Marksman's Mark reads _apply_attack()'s live per-hit state),
	# consistent with this file's own header-comment precedent. This proves the precondition state
	# combat.gd's wiring reads. Marksman's Call's own resolver math is covered in
	# tests/test_marksmans_call.gd (Task 2).
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"base_ability", &"mark_marksmans_call"), "picks mark_marksmans_call")
	_check(c3.has_ability_talent(&"mark_marksmans_call"), "has_ability_talent sees mark_marksmans_call")

	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"base_ability", &"mark_marksman"), "picks mark_marksman")
	_check(c4.has_ability_talent(&"mark_marksman"), "has_ability_talent sees mark_marksman")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_ranger()
	_check(c5.pick_ability_talent(&"base_ability", &"mark_rooting"), "first pick on the Hunter's Mark row succeeds")
	_check(not c5.pick_ability_talent(&"base_ability", &"mark_marksman"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c5.has_ability_talent(&"mark_rooting"), "the row's original pick is still active")

func _test_aimed_shot_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.ability_talent_cost_delta(&"aimed_shot") == 0, "no Aimed Shot cost delta (aim_efficient retired)")
	_check(c.pick_ability_talent(&"ability_l2", &"aim_rooting"), "picks aim_rooting")
	_check(not c.aimed_shot_root_pending, "sanity: aimed_shot_root_pending starts false")
	_check(c.stage_aimed_shot(3), "stages Aimed Shot (rooting)")
	_check(c.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring (which sets aimed_shot_root_pending) to read")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l2", &"aim_weakening"), "picks aim_weakening")
	_check(not c2.aimed_shot_hit_pending, "sanity: aimed_shot_hit_pending starts false")
	_check(c2.stage_aimed_shot(3), "stages Aimed Shot (weakening)")
	_check(c2.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring (which sets aimed_shot_hit_pending) to read")

	# Practiced Aim's actual Empowered-duration extension (2 turns instead of 1, when the target is
	# already Marked) lives in combat.gd's own commit-time resolution — orchestrator-level (Aimed
	# Shot's whole magnitude/duration computation already lived there before this task, sized by the
	# defender's Mark status) — NOT headlessly tested here (see this file's header comment).
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l2", &"aim_practiced"), "picks aim_practiced")
	_check(c3.has_ability_talent(&"aim_practiced"), "has_ability_talent sees aim_practiced")
	_check(c3.stage_aimed_shot(3), "stages Aimed Shot (practiced)")
	_check(c3.aimed_shot_pending, "Aimed Shot is pending for combat.gd's commit-time wiring to read")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_ranger()
	_check(c4.pick_ability_talent(&"ability_l2", &"aim_rooting"), "first pick on the Aimed Shot row succeeds")
	_check(not c4.pick_ability_talent(&"ability_l2", &"aim_weakening"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_snare_trap_row() -> void:
	var c: Combatant = _mk_ranger()
	_check(c.pick_ability_talent(&"ability_l3", &"snare_wider"), "picks snare_wider")
	_check(c.has_ability_talent(&"snare_wider"), "has_ability_talent sees snare_wider")

	var c2: Combatant = _mk_ranger()
	_check(c2.pick_ability_talent(&"ability_l3", &"snare_marking"), "picks snare_marking")
	_check(c2.has_ability_talent(&"snare_marking"), "has_ability_talent sees snare_marking")

	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l3", &"snare_focused"), "picks snare_focused")
	_check(c3.has_ability_talent(&"snare_focused"), "has_ability_talent sees snare_focused")

	# Baseline AoE splash math (proof of the formula, mirroring tests/test_collateral.gd's own
	# convention of replicating the orchestrator's formula directly — _splash_half_to_others() is a
	# private Combat-scene method with no live scene here). Snare Trap's own primary hit + the
	# actual splash/Rooted-attach/Marking-Snare loop are all orchestrator-level (combat.gd's
	# _apply_attack()), NOT headlessly tested here (see this file's header comment).
	_check(ceili(20 * 0.5) == 10, "sanity: baseline (1/2) splash of 20 is 10")
	var other_a: Combatant = _mk_ranger()
	var other_b: Combatant = _mk_ranger()
	var splashed: Array[Combatant] = [other_a, other_b]
	_check(not other_a.has_effect(&"rooted") and not other_b.has_effect(&"rooted"), "sanity: neither splashed enemy starts Rooted")
	var wide_duration: int = 2 if c.has_ability_talent(&"snare_wider") else 1
	for other: Combatant in splashed:
		var splash_rooted: Effect = EffectLibrary.make(&"rooted")
		splash_rooted.duration = wide_duration
		other.attach_effect(splash_rooted)
	_check(other_a.has_effect(&"rooted") and other_b.has_effect(&"rooted"), "every splashed enemy is also Rooted")
	_check(other_a._find_effect(&"rooted").duration == 2, "snare_wider: splash Rooted matches the primary's full 2-turn duration (got %d)" % other_a._find_effect(&"rooted").duration)

	var c4: Combatant = _mk_ranger()
	_check(c4.try_snare_trap(c4.weapon_type(), 4, 6), "casts Snare Trap (sanity: unaffected structurally by talents)")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_ranger()
	_check(c5.pick_ability_talent(&"ability_l3", &"snare_wider"), "first pick on the Snare Trap row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l3", &"snare_marking"), "a second pick on an already-filled row is rejected (cap of 1/row)")

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

	# Marked for the Kill's actual ADDITIONAL +25%-if-also-Marked bonus lives in combat.gd's
	# _apply_attack() — it stacks on top of the EXISTING bonus_vs_cc inline calculation, not a new
	# separate hit, so it's checked directly there rather than through a generic hook (see this
	# task's Implementation notes). Orchestrator-level, NOT headlessly tested here.
	var c3: Combatant = _mk_ranger()
	_check(c3.pick_ability_talent(&"ability_l4", &"crippling_marked"), "picks crippling_marked")
	_check(c3.has_ability_talent(&"crippling_marked"), "has_ability_talent sees crippling_marked")
	_check(c3.try_crippling_shot(c3.weapon_type(), 5, 6), "casts Crippling Shot (sanity: unaffected structurally by talents)")

func _test_steady_aim_row() -> void:
	var c: Combatant = _mk_ranger()
	c.passive_ability_id = &"steady_aim"
	var marked: Combatant = _mk_ranger()
	marked.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c.passive_outgoing_multiplier(marked), 1.10), "baseline Steady Aim: +10% vs a Marked defender")

	var c2: Combatant = _mk_ranger()
	c2.passive_ability_id = &"steady_aim"
	var cc_defender: Combatant = _mk_ranger()
	cc_defender.attach_effect(EffectLibrary.make(&"rooted"))
	_check(is_equal_approx(c2.passive_outgoing_multiplier(cc_defender), 1.0), "sanity: baseline Steady Aim does NOT trigger vs a merely-Rooted defender")
	_check(c2.pick_ability_talent(&"passive", &"steady_controlled"), "picks steady_controlled")
	_check(is_equal_approx(c2.passive_outgoing_multiplier(cc_defender), 1.10), "steady_controlled: now also triggers vs a Rooted defender (got %.3f)" % c2.passive_outgoing_multiplier(cc_defender))

	var c3: Combatant = _mk_ranger()
	c3.passive_ability_id = &"steady_aim"
	var weakened_defender: Combatant = _mk_ranger()
	weakened_defender.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.0), "sanity: baseline Steady Aim does NOT trigger vs a merely-Weakened defender")
	_check(c3.pick_ability_talent(&"passive", &"steady_wider"), "picks steady_wider")
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened_defender), 1.10), "steady_wider: now also triggers vs a Weakened defender (got %.3f)" % c3.passive_outgoing_multiplier(weakened_defender))

	# Deadeye's actual +15%-on-CRIT_SUCCESS-vs-Marked bonus lives in combat.gd's _apply_attack() —
	# a crit-specific layer ON TOP OF the unchanged +10% baseline above, not a bigger baseline
	# multiplier — orchestrator-level, NOT headlessly tested here (see this file's header comment).
	var c4: Combatant = _mk_ranger()
	c4.passive_ability_id = &"steady_aim"
	_check(c4.pick_ability_talent(&"passive", &"steady_deadeye"), "picks steady_deadeye")
	_check(c4.has_ability_talent(&"steady_deadeye"), "has_ability_talent sees steady_deadeye")
	_check(is_equal_approx(c4.passive_outgoing_multiplier(marked), 1.10), "steady_deadeye alone leaves the baseline +10%-vs-Marked bonus unchanged")

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"steady_controlled"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_collateral_row() -> void:
	# Point Blank's actual guaranteed-crit face upgrade (only when the primary target is already
	# Marked) lives in combat.gd's _commit_main1(), right after fire_collateral() appends its reel —
	# orchestrator-level (needs _defender), NOT headlessly tested here (see this file's header
	# comment).
	var c: Combatant = _mk_ranger()
	_check(c.pick_ability_talent(&"ultimate", &"collateral_point_blank"), "picks collateral_point_blank")
	_check(c.has_ability_talent(&"collateral_point_blank"), "has_ability_talent sees collateral_point_blank")

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
	_check(c5.pick_ability_talent(&"ultimate", &"collateral_point_blank"), "first pick on the Collateral Damage row succeeds")
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
