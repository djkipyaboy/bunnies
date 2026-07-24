extends SceneTree

# Headless test: the Chancer's 18 Ability Talent options (Task 18) — one row of 3 mutually-
# exclusive picks per Chancer ability (Re-roll / Loaded Dice / Jinx the Odds / Double or Nothing /
# House Edge / Wildcard Gamble). Exercises AbilityTalentLibrary.options_for(&"chancer", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and the
# GENERIC apply_rider_talent_adjustments()/rider_talent_bonus_damage_pct() hooks (Jinx the Odds'
# &"jinxed" rider id is unique to this ability — unlike Vanguard's Quake Slam, no reel-instance-scoped
# workaround is needed here; see this task's Implementation notes).
#
# reroll_deeper's post-reroll bonus-damage application, reroll_double's/wildcard_gamble's own re-roll
# LOOP, gamble_refunding's per-reel Mana-refund tally, and wildcard_lucky's post-resolve meter refund
# all live in combat.gd's _apply_post_spin_rerolls()/_apply_attack()/_finish_spin() — orchestrator-
# level, requires a running Combat scene — and are NOT headlessly tested here, consistent with this
# codebase's own documented precedent (tests/test_ability_talents_warrior.gd's header comment on
# Bleeding Wild). Where the underlying arithmetic is a genuine pure static helper (reroll_deeper_damage,
# worst_reroll_index's new exclude param, gamble_final_damage's new crit_mult/fail_pct params), this
# test proves that helper directly instead — the actual reusable logic combat.gd's wiring calls.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_chancer.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_chancer() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"chancer").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.mana = c.resource_pool.max_mana
	c.begin_turn()  # populates turn_reels from the 4-reel Storm Sling
	return c

## Mirrors tests/test_reroll_selection.gd's own helper — a bare AttackResult carrying just a tier,
## enough to drive worst_reroll_index()/gamble_final_damage() without a live spin.
func _mk(tier: ReelFace.ResultTier) -> CombatResolver.AttackResult:
	var a: CombatResolver.AttackResult = CombatResolver.AttackResult.new()
	var f: ReelFace = ReelFace.new(); f.result_tier = tier
	a.face = f
	return a

func _count_crit_faces_with_mult(reel: ActionReel, mult: float) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and is_equal_approx(f.multiplier, mult):
			n += 1
	return n

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"reroll_deeper", &"reroll_double", &"reroll_efficient",
		&"dice_deeper", &"dice_lucky", &"dice_efficient",
		&"jinx_deeper", &"jinx_lasting", &"jinx_efficient",
		&"gamble_deeper", &"gamble_refunding", &"gamble_swift",
		&"edge_deeper", &"edge_lucky", &"edge_wider",
		&"wildcard_deeper", &"wildcard_safer", &"wildcard_lucky",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"chancer", row)
		_check(opts.size() == 3, "Chancer row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&chancer, ...)" % id)

func _test_reroll_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cost_delta(&"reroll") == 0, "no Re-roll cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"reroll_efficient"), "picks reroll_efficient")
	_check(c.ability_talent_cost_delta(&"reroll") == -1, "reroll_efficient: Re-roll costs 1 less Mana")

	# reroll_deeper_damage() is a pure static helper (mirrors bloodwrath_bonus_pct/gamble_final_damage's
	# own static-pure precedent, specifically so it's directly testable) — proves the real +10% math
	# combat.gd's _apply_post_spin_rerolls() calls after a re-roll lands a hit.
	_check(Combatant.reroll_deeper_damage(100) == 110, "reroll_deeper_damage: +10%% bonus damage (got %d)" % Combatant.reroll_deeper_damage(100))
	var c2: Combatant = _mk_chancer()
	_check(c2.pick_ability_talent(&"base_ability", &"reroll_deeper"), "picks reroll_deeper")
	_check(c2.has_ability_talent(&"reroll_deeper"), "has_ability_talent sees reroll_deeper")

	# reroll_double: worst_reroll_index()'s new [param exclude] (Task 18) is the real primitive
	# combat.gd's re-roll loop uses to pick a SECOND reel without re-picking the first.
	var attacks_a: Array = [_mk(ReelFace.ResultTier.CRIT_FAILURE), _mk(ReelFace.ResultTier.FAILURE), _mk(ReelFace.ResultTier.NEUTRAL)]
	_check(Combatant.worst_reroll_index(attacks_a) == 0, "sanity: worst_reroll_index still picks the first crit-fail with no exclusions")
	_check(Combatant.worst_reroll_index(attacks_a, [0]) == 1, "worst_reroll_index skips an excluded index — reroll_double's 2nd pick (got %d)" % Combatant.worst_reroll_index(attacks_a, [0]))
	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"base_ability", &"reroll_double"), "picks reroll_double")
	_check(c3.has_ability_talent(&"reroll_double"), "has_ability_talent sees reroll_double")

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_chancer()
	_check(c4.pick_ability_talent(&"base_ability", &"reroll_efficient"), "first pick on the Re-roll row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"reroll_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"reroll_efficient"), "the row's original pick is still active")

func _test_loaded_dice_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cost_delta(&"loaded_dice") == 0, "no Loaded Dice cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"dice_efficient"), "picks dice_efficient")
	_check(c.ability_talent_cost_delta(&"loaded_dice") == -1, "dice_efficient: Loaded Dice costs 1 less Mana")

	var c2: Combatant = _mk_chancer()
	_check(_count_crit_faces_with_mult(c2.turn_reels[0], 2.0) == 1, "sanity: a fresh Storm Sling reel has exactly 1 native x2.0 crit face")
	_check(c2.apply_loaded_dice(3), "casts Loaded Dice (baseline)")
	_check(_count_crit_faces_with_mult(c2.turn_reels[0], 2.0) == 2, "baseline Loaded Dice: adds a 2nd x2.0 crit face (got %d)" % _count_crit_faces_with_mult(c2.turn_reels[0], 2.0))

	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"ability_l2", &"dice_deeper"), "picks dice_deeper")
	_check(c3.apply_loaded_dice(3), "casts Loaded Dice (deeper)")
	_check(_count_crit_faces_with_mult(c3.turn_reels[0], 2.0) == 1, "dice_deeper: the native x2.0 crit face is untouched")
	_check(_count_crit_faces_with_mult(c3.turn_reels[0], 2.25) == 1, "dice_deeper: the ADDED crit face is x2.25 instead (got %d)" % _count_crit_faces_with_mult(c3.turn_reels[0], 2.25))

	var c4: Combatant = _mk_chancer()
	c4.bonus_meter.value = 0
	_check(c4.pick_ability_talent(&"ability_l2", &"dice_lucky"), "picks dice_lucky")
	_check(c4.apply_loaded_dice(3), "casts Loaded Dice (lucky)")
	_check(c4.bonus_meter.value == 1, "dice_lucky: +1 flat Bonus Meter charge on cast (got %d)" % c4.bonus_meter.value)

func _test_jinx_the_odds_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cost_delta(&"jinx_the_odds") == 0, "no Jinx the Odds cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"jinx_efficient"), "picks jinx_efficient")
	_check(c.ability_talent_cost_delta(&"jinx_the_odds") == -1, "jinx_efficient: Jinx the Odds costs 1 less Mana")

	var c2: Combatant = _mk_chancer()
	_check(c2.pick_ability_talent(&"ability_l3", &"jinx_deeper"), "picks jinx_deeper")
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"jinxed"), 0.15), "jinx_deeper: +15%% bonus damage on Jinx the Odds' own hit (got %.3f)" % c2.rider_talent_bonus_damage_pct(&"jinxed"))
	_check(is_equal_approx(c2.rider_talent_bonus_damage_pct(&"weakened"), 0.0), "jinx_deeper only applies to the jinxed rider id, not any other")

	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"ability_l3", &"jinx_lasting"), "picks jinx_lasting")
	var jinxed: Effect = EffectLibrary.make(&"jinxed")
	_check(jinxed.duration == 2, "sanity: Jinxed's baseline duration is 2")
	c3.apply_rider_talent_adjustments(&"jinxed", jinxed, c3)
	_check(jinxed.duration == 3, "jinx_lasting: Jinxed lasts 3 turns (got %d)" % jinxed.duration)

	var c4: Combatant = _mk_chancer()
	_check(c4.try_jinx_the_odds(c4.weapon_type(), 3, 6), "casts Jinx the Odds (sanity: unaffected by talents)")

func _test_double_or_nothing_row() -> void:
	var c: Combatant = _mk_chancer()
	_check(c.ability_talent_cooldown_delta(&"double_or_nothing") == 0, "no Double or Nothing cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"gamble_swift"), "picks gamble_swift")
	_check(c.ability_talent_cooldown_delta(&"double_or_nothing") == -1, "gamble_swift: Double or Nothing's cooldown is 1 less turn")

	var c2: Combatant = _mk_chancer()
	_check(c2.fire_double_or_nothing(c2.weapon_type(), 6), "fires Double or Nothing (baseline)")
	var emp: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp.magnitude, 2.0), "baseline Double or Nothing: Empowered is x2.0")

	var c3: Combatant = _mk_chancer()
	_check(c3.pick_ability_talent(&"ability_l4", &"gamble_deeper"), "picks gamble_deeper")
	_check(c3.fire_double_or_nothing(c3.weapon_type(), 6), "fires Double or Nothing (deeper)")
	var emp2: Effect = c3._find_effect(&"empowered")
	_check(is_equal_approx(emp2.magnitude, 2.25), "gamble_deeper: Empowered is x2.25 (got %.3f)" % emp2.magnitude)

	# gamble_refunding's actual +1 extra Mana per non-recoil reel is tallied in combat.gd's
	# _apply_attack() per-reel loop — orchestrator-level, NOT headlessly tested here (see this file's
	# header comment).
	var c4: Combatant = _mk_chancer()
	_check(c4.pick_ability_talent(&"ability_l4", &"gamble_refunding"), "picks gamble_refunding")
	_check(c4.has_ability_talent(&"gamble_refunding"), "has_ability_talent sees gamble_refunding")
	_check(c4.fire_double_or_nothing(c4.weapon_type(), 6), "fires Double or Nothing (refunding) — precondition state for combat.gd's wiring")
	_check(c4.double_or_nothing_pending, "Double or Nothing is pending for combat.gd's per-reel refund-accum check to read")

func _test_house_edge_row() -> void:
	var c: Combatant = _mk_chancer()
	c.passive_ability_id = &"house_edge"
	c.bonus_meter.value = 0
	c.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c.bonus_meter.value == 1, "baseline House Edge: +1 charge on any scored payline (got %d)" % c.bonus_meter.value)

	var c2: Combatant = _mk_chancer()
	c2.passive_ability_id = &"house_edge"
	c2.bonus_meter.value = 0
	_check(c2.pick_ability_talent(&"passive", &"edge_deeper"), "picks edge_deeper")
	c2.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	_check(c2.bonus_meter.value == 2, "edge_deeper: +2 charge on a scored payline (got %d)" % c2.bonus_meter.value)

	# edge_lucky: a genuine 25%% coin flip, not a deterministic branch — checked statistically, the
	# same technique tests/test_ultimate_sticky_wild.gd uses for WILD_CRIT_CHANCE.
	var c3: Combatant = _mk_chancer()
	c3.passive_ability_id = &"house_edge"
	c3.bonus_meter.value = 0
	c3.resource_pool.max_mana = 999
	c3.resource_pool.mana = 0
	_check(c3.pick_ability_talent(&"passive", &"edge_lucky"), "picks edge_lucky")
	var trials: int = 400
	for i: int in range(trials):
		c3.passive_on_payline_scored(ReelFace.ResultTier.SUCCESS)
	var rate: float = float(c3.resource_pool.mana) / float(trials)
	_check(rate >= 0.15 and rate <= 0.35, "edge_lucky: ~25%% of scored paylines also refund 1 Mana (got %.3f)" % rate)

	# edge_wider's actual NEUTRAL-tier-reel trigger lives in combat.gd's _apply_attack() —
	# orchestrator-level, NOT headlessly tested here (see this file's header comment and this task's
	# Implementation notes on the chosen reading of its wording).
	var c4: Combatant = _mk_chancer()
	c4.passive_ability_id = &"house_edge"
	_check(c4.pick_ability_talent(&"passive", &"edge_wider"), "picks edge_wider")
	_check(c4.has_ability_talent(&"edge_wider"), "has_ability_talent sees edge_wider")

	# Mutual exclusion (passive row): only 1 pick per row.
	_check(not c4.pick_ability_talent(&"passive", &"edge_deeper"), "a second pick on an already-filled row is rejected (cap of 1/row)")

func _test_wildcard_gamble_row() -> void:
	var CS := ReelFace.ResultTier.CRIT_SUCCESS
	var F := ReelFace.ResultTier.FAILURE
	var CF := ReelFace.ResultTier.CRIT_FAILURE

	_check(Combatant.gamble_final_damage(CS, 10) == 20, "sanity: baseline gamble_final_damage crit is still x2.0")
	_check(Combatant.gamble_final_damage(CS, 10, 2.25) == 23, "wildcard_deeper: crit reroll multiplies x2.25, rounded up (got %d)" % Combatant.gamble_final_damage(CS, 10, 2.25))

	_check(Combatant.gamble_final_damage(F, 10) == 0, "sanity: baseline gamble_final_damage still zeroes a failed reroll")
	_check(Combatant.gamble_final_damage(F, 10, 2.0, 0.25) == 3, "wildcard_safer: a failed reroll still deals 25%% (ceil, got %d)" % Combatant.gamble_final_damage(F, 10, 2.0, 0.25))
	_check(Combatant.gamble_final_damage(CF, 10, 2.0, 0.25) == 3, "wildcard_safer applies identically to a crit-failed reroll")

	var c: Combatant = _mk_chancer()
	_check(c.pick_ability_talent(&"ultimate", &"wildcard_deeper"), "picks wildcard_deeper")
	_check(c.has_ability_talent(&"wildcard_deeper"), "has_ability_talent sees wildcard_deeper")

	var c2: Combatant = _mk_chancer()
	_check(c2.pick_ability_talent(&"ultimate", &"wildcard_safer"), "picks wildcard_safer")
	_check(c2.has_ability_talent(&"wildcard_safer"), "has_ability_talent sees wildcard_safer")

	# wildcard_lucky's actual +1 Bonus Meter refund lives in combat.gd's _finish_spin() —
	# orchestrator-level, NOT headlessly tested here. This proves fire_wildcard_gamble()'s own
	# precondition state (wildcard_gamble_pending) that _finish_spin's wiring reads.
	var c3: Combatant = _mk_chancer()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"wildcard_lucky"), "picks wildcard_lucky")
	_check(c3.fire_wildcard_gamble(), "fires Wildcard Gamble (lucky)")
	_check(c3.wildcard_gamble_pending, "Wildcard Gamble is pending for combat.gd's finish-spin refund check to read")

func _init() -> void:
	_test_options_for_shape()
	_test_reroll_row()
	_test_loaded_dice_row()
	_test_jinx_the_odds_row()
	_test_double_or_nothing_row()
	_test_house_edge_row()
	_test_wildcard_gamble_row()
	print(("CHANCER ABILITY TALENTS TEST PASSED" if _failures == 0 else "CHANCER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
