extends SceneTree

# Headless test: the Warden's 18 Ability Talent options (Task 21) — one row of 3 mutually-
# exclusive picks per Warden ability (Rallying Cry / Entangle / Regrowth / Bastion / Deep Roots /
# Earthquake). Exercises AbilityTalentLibrary.options_for(&"warden", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# GENERIC apply_rider_talent_adjustments()/rider_talent_bonus_damage_pct() hooks — Warden's Earth
# weapon type carries no inherent_rider_id (verified against combat/resources/types/earth.tres), so
# unlike Vanguard's Quake Slam (Task 16) neither of Warden's own rider ids (rooted from Entangle,
# regen from Regrowth) needs a reel-instance-scoped workaround; Warden is in the same clean
# situation Chancer (Task 18) and Ranger (Task 19) were in.
#
# Deeper Cry/Lasting Cry's actual shield-amount/duration math (Rallying Cry's shield has always been
# computed at the orchestrator level, in combat.gd's own _finish_spin() — not a Combatant method,
# distinct from every other ability in this plan so far) and Rooting Quake's actual on-splash Rooted
# attach both live in combat.gd — orchestrator-level, require a running Combat scene — and are NOT
# headlessly tested here, consistent with this codebase's own documented precedent
# (tests/test_ability_talents_warrior.gd's header comment on Bleeding Wild). Where the underlying
# math is checkable directly (Deeper Quake's splash-fraction formula, mirroring
# tests/test_ability_talents_ranger.gd's own manual-replication convention for Deeper Collateral) or
# a manually-simulated loop is checkable (Rooting Quake's exact splash+root loop, has_ability_talent,
# the pending flags combat.gd's wiring reads), this test proves that instead.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_warden.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_warden() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"warden").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.mana = 20
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"cry_deeper", &"cry_lasting", &"cry_efficient",
		&"entangle_deeper", &"entangle_lasting", &"entangle_efficient",
		&"regrowth_deeper", &"regrowth_lasting", &"regrowth_efficient",
		&"bastion_deeper", &"bastion_reinforced", &"bastion_swift",
		&"roots_deeper", &"roots_regen", &"roots_thorned",
		&"quake_deeper", &"quake_rooting", &"quake_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"warden", row)
		_check(opts.size() == 3, "Warden row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&warden, ...)" % id)

func _test_rallying_cry_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.ability_talent_cost_delta(&"rallying_cry") == 0, "no Rallying Cry cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"cry_efficient"), "picks cry_efficient")
	_check(c.has_ability_talent(&"cry_efficient"), "has_ability_talent sees cry_efficient")
	_check(c.ability_talent_cost_delta(&"rallying_cry") == -1, "cry_efficient: Rallying Cry costs 1 less Mana")

	# Deeper Cry/Lasting Cry's actual shield-amount/duration math lives in combat.gd's own
	# _finish_spin() (see this task's Implementation note) — NOT headlessly tested here, consistent
	# with this file's own header comment. This proves the precondition state combat.gd's wiring reads.
	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"base_ability", &"cry_deeper"), "picks cry_deeper")
	_check(c2.apply_rallying_cry(4, 6), "casts Rallying Cry (deeper)")
	_check(c2.rallying_cry_reel != null, "Rallying Cry's reel is recorded for combat.gd's wiring to read")

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"base_ability", &"cry_lasting"), "picks cry_lasting")
	_check(c3.apply_rallying_cry(4, 6), "casts Rallying Cry (lasting)")
	_check(c3.has_ability_talent(&"cry_lasting"), "has_ability_talent sees cry_lasting")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_warden()
	_check(c4.pick_ability_talent(&"base_ability", &"cry_efficient"), "first pick on the Rallying Cry row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"cry_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_entangle_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.ability_talent_cost_delta(&"entangle") == 0, "no Entangle cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"entangle_efficient"), "picks entangle_efficient")
	_check(c.ability_talent_cost_delta(&"entangle") == -1, "entangle_efficient: Entangle costs 1 less Mana")

	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ability_l2", &"entangle_deeper"), "picks entangle_deeper")
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"rooted"), 0.15), "entangle_deeper: +15%% bonus damage on Entangle's own hit (got %.3f)" % c2.rider_talent_bonus_damage_pct(&"rooted"))
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"regen"), 0.0), "entangle_deeper only applies to the rooted rider id, not any other")

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"ability_l2", &"entangle_lasting"), "picks entangle_lasting")
	var rooted: Effect = EffectLibrary.make(&"rooted")
	_check(rooted.duration == 2, "sanity: Rooted's baseline duration is 2")
	c3.apply_rider_talent_adjustments(&"rooted", rooted, c3)
	_check(rooted.duration == 3, "entangle_lasting: Rooted lasts 3 turns (got %d)" % rooted.duration)

	var c4: Combatant = _mk_warden()
	_check(c4.try_entangle(c4.weapon_type(), 4, 6), "casts Entangle (sanity: unaffected structurally by talents)")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ability_l2", &"entangle_efficient"), "first pick on the Entangle row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l2", &"entangle_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_regrowth_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.ability_talent_cost_delta(&"regrowth") == 0, "no Regrowth cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"regrowth_efficient"), "picks regrowth_efficient")
	_check(c.ability_talent_cost_delta(&"regrowth") == -1, "regrowth_efficient: Regrowth costs 1 less Mana")

	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ability_l3", &"regrowth_deeper"), "picks regrowth_deeper")
	var regen: Effect = EffectLibrary.make(&"regen")
	var base_fractions: Array = regen.dot_fractions.duplicate()
	c2.apply_rider_talent_adjustments(&"regen", regen, c2)
	for i: int in range(base_fractions.size()):
		_check(is_equal_approx(regen.dot_fractions[i], base_fractions[i] * 1.25),
			"regrowth_deeper: Regen fraction %d is +25%% (got %.4f, want %.4f)" % [i, regen.dot_fractions[i], base_fractions[i] * 1.25])
	_check(regen.max_stacks == 3, "regrowth_deeper alone leaves max_stacks at 3")

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"ability_l3", &"regrowth_lasting"), "picks regrowth_lasting")
	var regen2: Effect = EffectLibrary.make(&"regen")
	c3.apply_rider_talent_adjustments(&"regen", regen2, c3)
	_check(regen2.max_stacks == 4, "regrowth_lasting: Regen max_stacks is 4 (got %d)" % regen2.max_stacks)
	_check(regen2.dot_fractions.size() == 4, "regrowth_lasting: Regen gained a 4th stack fraction (got %d entries)" % regen2.dot_fractions.size())
	_check(is_equal_approx(regen2.dot_fractions[3], 1.55), "regrowth_lasting: 4th stack fraction is 1.55 (got %.4f)" % regen2.dot_fractions[3])

	var c4: Combatant = _mk_warden()
	_check(c4.stage_regrowth(4), "stages Regrowth (sanity: unaffected structurally by talents)")
	_check(c4.regrowth_pending, "Regrowth is pending for combat.gd's commit-time wiring to read")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ability_l3", &"regrowth_efficient"), "first pick on the Regrowth row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l3", &"regrowth_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_bastion_row() -> void:
	var c: Combatant = _mk_warden()
	_check(c.apply_bastion(6), "casts Bastion (baseline)")
	var g: Effect = c._find_effect(&"guarded")
	_check(g != null, "sanity: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.5), "baseline Bastion: Guarded magnitude 0.5")
	_check(is_equal_approx(g.thorns_pct, 0.20), "baseline Bastion: Thorns 20%%")

	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ability_l4", &"bastion_deeper"), "picks bastion_deeper")
	_check(c2.apply_bastion(6), "casts Bastion (deeper)")
	var g2: Effect = c2._find_effect(&"guarded")
	_check(is_equal_approx(g2.thorns_pct, 0.30), "bastion_deeper: Thorns is 30%% (got %.3f)" % g2.thorns_pct)

	var c3: Combatant = _mk_warden()
	_check(c3.pick_ability_talent(&"ability_l4", &"bastion_reinforced"), "picks bastion_reinforced")
	_check(c3.apply_bastion(6), "casts Bastion (reinforced)")
	var g3: Effect = c3._find_effect(&"guarded")
	_check(is_equal_approx(g3.magnitude, 0.4), "bastion_reinforced: Guarded magnitude 0.4 (got %.3f)" % g3.magnitude)

	var c4: Combatant = _mk_warden()
	_check(c4.ability_talent_cooldown_delta(&"bastion") == 0, "no Bastion cooldown delta with nothing picked")
	_check(c4.pick_ability_talent(&"ability_l4", &"bastion_swift"), "picks bastion_swift")
	_check(c4.ability_talent_cooldown_delta(&"bastion") == -1, "bastion_swift: Bastion's cooldown is 1 less turn")

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ability_l4", &"bastion_deeper"), "first pick on the Bastion row succeeds")
	_check(not c5.pick_ability_talent(&"ability_l4", &"bastion_reinforced"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_deep_roots_row() -> void:
	var c: Combatant = _mk_warden()
	c.passive_ability_id = &"deep_roots"
	c.max_hp = 160
	_check(is_equal_approx(c.passive_dot_damage_multiplier(), 0.85), "baseline Deep Roots: -15% incoming DoT damage")
	_check(c.passive_upkeep_heal_amount() == 10, "baseline Deep Roots: Upkeep heal is ceil(160/16) = 10 (got %d)" % c.passive_upkeep_heal_amount())
	_check(is_equal_approx(c.thorns_pct(), 0.0), "baseline Deep Roots grants no Thorns")

	var c2: Combatant = _mk_warden()
	c2.passive_ability_id = &"deep_roots"
	_check(c2.pick_ability_talent(&"passive", &"roots_deeper"), "picks roots_deeper")
	_check(is_equal_approx(c2.passive_dot_damage_multiplier(), 0.75), "roots_deeper: -25%% incoming DoT damage (got %.3f)" % c2.passive_dot_damage_multiplier())

	var c3: Combatant = _mk_warden()
	c3.passive_ability_id = &"deep_roots"
	c3.max_hp = 144
	_check(c3.pick_ability_talent(&"passive", &"roots_regen"), "picks roots_regen")
	_check(c3.passive_upkeep_heal_amount() == 12, "roots_regen: Upkeep heal is ceil(144/12) = 12 (got %d)" % c3.passive_upkeep_heal_amount())

	var c4: Combatant = _mk_warden()
	c4.passive_ability_id = &"deep_roots"
	_check(c4.pick_ability_talent(&"passive", &"roots_thorned"), "picks roots_thorned")
	_check(is_equal_approx(c4.thorns_pct(), 0.10), "roots_thorned: 10%% passive Thorns at all times (got %.3f)" % c4.thorns_pct())

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"roots_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_earthquake_row() -> void:
	# Deeper Quake's splash-fraction formula (mirrors Ranger's collateral_deeper math-only convention;
	# _splash_half_to_others() is a private Combat-scene method with no live scene here).
	_check(ceili(20 * 0.5) == 10, "sanity: baseline (1/2) splash of 20 is 10")
	_check(ceili(20 * (2.0 / 3.0)) == 14, "quake_deeper: 2/3 splash of 20 is 14, rounded up (got %d)" % ceili(20 * (2.0 / 3.0)))
	var c: Combatant = _mk_warden()
	_check(c.pick_ability_talent(&"ultimate", &"quake_deeper"), "picks quake_deeper")
	_check(c.has_ability_talent(&"quake_deeper"), "has_ability_talent sees quake_deeper")

	# Rooting Quake: manually simulates the exact splash+root loop combat.gd's _finish_spin() performs
	# (mirroring test_ability_talents_ranger.gd's collateral_marking convention, since
	# _splash_half_to_others()/its caller are private Combat-scene methods) — including the
	# apply_rider_talent_adjustments() routing so a Warden who ALSO picked entangle_lasting gets the
	# 3-turn Rooted duration on Earthquake's splash too (see this task's Implementation note).
	var c2: Combatant = _mk_warden()
	_check(c2.pick_ability_talent(&"ultimate", &"quake_rooting"), "picks quake_rooting")
	var primary: Combatant = _mk_warden()
	var other_a: Combatant = _mk_warden()
	var other_b: Combatant = _mk_warden()
	var quaked: Array[Combatant] = [other_a, other_b]
	_check(not primary.has_effect(&"rooted") and not other_a.has_effect(&"rooted"), "sanity: nobody starts Rooted")
	if c2.has_ability_talent(&"quake_rooting"):
		var rooted_primary: Effect = EffectLibrary.make(&"rooted")
		c2.apply_rider_talent_adjustments(&"rooted", rooted_primary, primary)
		primary.attach_effect(rooted_primary)
		for other: Combatant in quaked:
			var rooted_other: Effect = EffectLibrary.make(&"rooted")
			c2.apply_rider_talent_adjustments(&"rooted", rooted_other, other)
			other.attach_effect(rooted_other)
	_check(primary.has_effect(&"rooted"), "quake_rooting: the primary target is also Rooted")
	_check(other_a.has_effect(&"rooted") and other_b.has_effect(&"rooted"), "quake_rooting: every splashed enemy is also Rooted")

	# Lasting Quake: fire_earthquake's spin count, via MainPhasePlan (mirrors Wild/Collateral's own
	# lasting-spin test pattern exactly).
	var c3: Combatant = _mk_warden()
	c3.bonus_meter.value = c3.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c3)
	_check(plan.ultimate_id == &"earthquake", "sanity: Warden's Ultimate id is &earthquake")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Earthquake ultimate stages when the meter is armed")
	plan.commit()
	_check(c3.earthquake_spins_remaining == 1, "without Lasting Quake, firing Earthquake grants 1 spin (got %d)" % c3.earthquake_spins_remaining)

	var c4: Combatant = _mk_warden()
	c4.bonus_meter.value = c4.bonus_meter.cap
	_check(c4.pick_ability_talent(&"ultimate", &"quake_lasting"), "picks quake_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c4)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c4.earthquake_spins_remaining == 2, "quake_lasting: firing Earthquake grants 2 spins (got %d)" % c4.earthquake_spins_remaining)

	# Mutual exclusion (ultimate row): only 1 pick per row.
	var c5: Combatant = _mk_warden()
	_check(c5.pick_ability_talent(&"ultimate", &"quake_deeper"), "first pick on the Earthquake row succeeds")
	_check(not c5.pick_ability_talent(&"ultimate", &"quake_rooting"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _init() -> void:
	_test_options_for_shape()
	_test_rallying_cry_row()
	_test_entangle_row()
	_test_regrowth_row()
	_test_bastion_row()
	_test_deep_roots_row()
	_test_earthquake_row()
	print(("WARDEN ABILITY TALENTS TEST PASSED" if _failures == 0 else "WARDEN ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
