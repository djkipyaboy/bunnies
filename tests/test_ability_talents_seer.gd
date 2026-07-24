extends SceneTree

# Headless test: the Seer's 18 Ability Talent options (Task 20) — one row of 3 mutually-exclusive
# picks per Seer ability (Select your Fate! / Hex / Foresight / Mana Surge / Arcane Reservoir /
# The Big Bang). Exercises AbilityTalentLibrary.options_for(&"seer", row_id),
# pick_ability_talent()/has_ability_talent(), the cost/cooldown-delta dispatch methods, and
# apply_rider_talent_adjustments() for the Cursed rider (no reel-instance-scoped workaround needed —
# Mystic has no inherent_rider_id, unlike Vanguard's Crushing/Task 16 — see this task's
# Implementation notes).
#
# fate_deeper/fate_wilder are tested directly against apply_select_fate()'s own constructed reel(s)
# (no rider to key a generic hook off — see Implementation note 2). Foresight's shield amount/
# duration and Big Bang's heal-divisor/shield-duration-bonus are tested via 4 small Combatant helper
# methods (foresight_shield_amount/duration, big_bang_heal_divisor, big_bang_shield_duration_bonus)
# that combat.gd's orchestrator-level blocks read — mirrors Vanguard's bloodwrath_bonus_pct()
# precedent (Task 16), so this math is unit-testable without a running Combat scene. bigbang_curing's
# actual cleanse-on-heal is proven by directly replicating the two orchestrator primitives it chains
# (heal() then cleanse()) — mirrors tests/test_ability_talents_ranger.gd's own "manual-replication"
# convention for an orchestrator-level effect whose underlying primitives are directly callable
# outside a running Combat scene.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_seer.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_seer() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.mana = c.resource_pool.max_mana
	c.begin_turn()  # populates turn_reels from the 2-reel Mystic War Staff
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"fate_deeper", &"fate_wilder", &"fate_efficient",
		&"hex_deeper", &"hex_lasting", &"hex_efficient",
		&"foresight_deeper", &"foresight_lasting", &"foresight_efficient",
		&"surge_deeper", &"surge_refunding", &"surge_swift",
		&"reservoir_deeper", &"reservoir_regen", &"reservoir_efficient",
		&"bigbang_deeper", &"bigbang_curing", &"bigbang_shielding",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"seer", row)
		_check(opts.size() == 3, "Seer row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&seer, ...)" % id)

func _test_select_fate_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cost_delta(&"select_fate") == 0, "no Select your Fate cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"fate_efficient"), "picks fate_efficient")
	_check(c.ability_talent_cost_delta(&"select_fate") == -1, "fate_efficient: Select your Fate costs 1 less Mana")

	var c2: Combatant = _mk_seer()
	var reels_before2: int = c2.turn_reels.size()
	_check(c2.pick_ability_talent(&"base_ability", &"fate_deeper"), "picks fate_deeper")
	_check(c2.apply_select_fate(c2.weapon_type(), 6), "casts Select your Fate (deeper)")
	_check(c2.turn_reels.size() == reels_before2 + 1, "sanity: Select your Fate adds exactly 1 reel")
	var added: ActionReel = c2.turn_reels[reels_before2]
	var hit_faces_checked: int = 0
	for f: ReelFace in added.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS:
			hit_faces_checked += 1
			_check(is_equal_approx(f.multiplier, 1.15), "fate_deeper: added reel's SUCCESS multiplier is +15%% (got %.4f)" % f.multiplier)
		elif f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_faces_checked += 1
			_check(is_equal_approx(f.multiplier, 2.3), "fate_deeper: added reel's CRIT_SUCCESS multiplier is +15%% (got %.4f)" % f.multiplier)
	_check(hit_faces_checked > 0, "sanity: the added reel has at least one hit face to check")

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"base_ability", &"fate_wilder"), "picks fate_wilder")
	_check(c3.apply_select_fate(c3.weapon_type(), 6), "casts Select your Fate (wilder)")
	for r: ActionReel in c3.turn_reels:
		var crit_count: int = 0
		for f: ReelFace in r.faces:
			if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				crit_count += 1
		_check(crit_count == 2, "fate_wilder: every one of this turn's reels gained an extra temporary crit face (1 baseline + 1 added, got %d)" % crit_count)

	# Mutual exclusion: only 1 pick per row.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"base_ability", &"fate_deeper"), "first pick on the Select your Fate row succeeds")
	_check(not c4.pick_ability_talent(&"base_ability", &"fate_wilder"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c4.has_ability_talent(&"fate_deeper"), "the row's original pick is still active")

func _test_hex_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cost_delta(&"hex") == 0, "no Hex cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"hex_efficient"), "picks hex_efficient")
	_check(c.ability_talent_cost_delta(&"hex") == -1, "hex_efficient: Hex costs 1 less Mana")

	var c2: Combatant = _mk_seer()
	_check(c2.pick_ability_talent(&"ability_l2", &"hex_deeper"), "picks hex_deeper")
	var cursed: Effect = EffectLibrary.make(&"cursed")
	var base_fractions: Array = cursed.dot_fractions.duplicate()
	c2.apply_rider_talent_adjustments(&"cursed", cursed, c2)
	for i: int in range(base_fractions.size()):
		_check(is_equal_approx(cursed.dot_fractions[i], base_fractions[i] * 1.25),
			"hex_deeper: Cursed fraction %d is +25%% (got %.4f, want %.4f)" % [i, cursed.dot_fractions[i], base_fractions[i] * 1.25])
	_check(cursed.max_stacks == 3, "hex_deeper alone leaves max_stacks at 3")

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ability_l2", &"hex_lasting"), "picks hex_lasting")
	var cursed2: Effect = EffectLibrary.make(&"cursed")
	c3.apply_rider_talent_adjustments(&"cursed", cursed2, c3)
	_check(cursed2.max_stacks == 4, "hex_lasting: Cursed max_stacks is 4 (got %d)" % cursed2.max_stacks)
	_check(cursed2.dot_fractions.size() == 4, "hex_lasting: Cursed gained a 4th stack fraction (got %d entries)" % cursed2.dot_fractions.size())
	_check(is_equal_approx(cursed2.dot_fractions[3], 1.55), "hex_lasting: 4th stack fraction is 1.55 (got %.4f)" % cursed2.dot_fractions[3])

	# Mutual exclusion.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"ability_l2", &"hex_efficient"), "first pick on the Hex row succeeds")
	_check(not c4.pick_ability_talent(&"ability_l2", &"hex_deeper"), "a second pick on an already-filled row is rejected")

func _test_foresight_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cost_delta(&"foresight") == 0, "no Foresight cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"foresight_efficient"), "picks foresight_efficient")
	_check(c.ability_talent_cost_delta(&"foresight") == -1, "foresight_efficient: Foresight costs 1 less Mana")

	var c2: Combatant = _mk_seer()
	var mm: int = c2.resource_pool.max_mana
	_check(c2.foresight_shield_amount() == ceili(mm * 0.15), "baseline Foresight shields 15%% of max Mana (got %d)" % c2.foresight_shield_amount())
	_check(c2.pick_ability_talent(&"ability_l3", &"foresight_deeper"), "picks foresight_deeper")
	_check(c2.foresight_shield_amount() == ceili(mm * 0.20), "foresight_deeper: shields 20%% of max Mana (got %d)" % c2.foresight_shield_amount())
	_check(c2.foresight_shield_duration() == 3, "foresight_deeper alone leaves duration at 3")

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ability_l3", &"foresight_lasting"), "picks foresight_lasting")
	_check(c3.foresight_shield_duration() == 4, "foresight_lasting: shield lasts 4 turns (got %d)" % c3.foresight_shield_duration())

func _test_mana_surge_row() -> void:
	var c: Combatant = _mk_seer()
	_check(c.ability_talent_cooldown_delta(&"mana_surge") == 0, "no Mana Surge cooldown delta with nothing picked")
	_check(c.apply_mana_surge(c.weapon_type(), 6, 5), "casts Mana Surge (baseline)")
	var emp: Effect = c._find_effect(&"empowered")
	_check(emp != null, "sanity: Empowered attached")
	_check(is_equal_approx(emp.magnitude, 1.6), "baseline Mana Surge: Empowered x1.6 (got %.3f)" % emp.magnitude)

	var c2: Combatant = _mk_seer()
	_check(c2.pick_ability_talent(&"ability_l4", &"surge_deeper"), "picks surge_deeper")
	_check(c2.apply_mana_surge(c2.weapon_type(), 6, 5), "casts Mana Surge (deeper)")
	var emp2: Effect = c2._find_effect(&"empowered")
	_check(is_equal_approx(emp2.magnitude, 1.75), "surge_deeper: Empowered x1.75 (got %.3f)" % emp2.magnitude)

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ability_l4", &"surge_refunding"), "picks surge_refunding")
	var mana_before: int = c3.resource_pool.mana
	_check(c3.apply_mana_surge(c3.weapon_type(), 8, 5), "casts Mana Surge (refunding, 8-cost cast)")
	_check(c3.resource_pool.mana == mana_before - 8 + 2, "surge_refunding: refunds 25%% of the 8-cost cast (2 Mana), net -6 (got %d, expected %d)" % [c3.resource_pool.mana, mana_before - 8 + 2])

	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"ability_l4", &"surge_swift"), "picks surge_swift")
	_check(c4.ability_talent_cooldown_delta(&"mana_surge") == -1, "surge_swift: Mana Surge cooldown is 1 less turn")

func _test_arcane_reservoir_row() -> void:
	var c: Combatant = _mk_seer()
	c.apply_stats()
	var baseline_max_mana: int = c.resource_pool.max_mana
	_check(is_equal_approx(c.passive_max_mana_multiplier(), 1.2), "baseline Arcane Reservoir: x1.2 max Mana")
	_check(c.pick_ability_talent(&"passive", &"reservoir_deeper"), "picks reservoir_deeper")
	_check(is_equal_approx(c.passive_max_mana_multiplier(), 1.35), "reservoir_deeper: x1.35 max Mana (got %.3f)" % c.passive_max_mana_multiplier())
	c.apply_stats()  # a real respec (TalentMenuPanel, a later task) re-derives stats the same way gear equip/unequip already does
	_check(c.resource_pool.max_mana > baseline_max_mana, "reservoir_deeper: max Mana increases once apply_stats() re-derives it (got %d, was %d)" % [c.resource_pool.max_mana, baseline_max_mana])

	var c2: Combatant = _mk_seer()
	c2.apply_stats()
	var before_regen: int = c2.resource_pool.mana_regen_per_turn
	_check(c2.pick_ability_talent(&"passive", &"reservoir_regen"), "picks reservoir_regen")
	c2.apply_stats()
	_check(c2.resource_pool.mana_regen_per_turn == before_regen + 1, "reservoir_regen: +1 flat Mana regen per Upkeep (got %d, was %d)" % [c2.resource_pool.mana_regen_per_turn, before_regen])

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"passive", &"reservoir_efficient"), "picks reservoir_efficient")
	_check(c3.ability_talent_cost_delta(&"select_fate") == -1, "reservoir_efficient: Select your Fate costs 1 less Mana")
	_check(c3.ability_talent_cost_delta(&"hex") == -1, "reservoir_efficient: Hex costs 1 less Mana")
	_check(c3.ability_talent_cost_delta(&"foresight") == -1, "reservoir_efficient: Foresight costs 1 less Mana")
	_check(c3.ability_talent_cost_delta(&"mana_surge") == -1, "reservoir_efficient: Mana Surge costs 1 less Mana")

	# Stacks with an ability's OWN "_efficient" pick — different rows, both allowed.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"base_ability", &"fate_efficient"), "picks fate_efficient (base_ability row)")
	_check(c4.pick_ability_talent(&"passive", &"reservoir_efficient"), "also picks reservoir_efficient (passive row — different row, both allowed)")
	_check(c4.ability_talent_cost_delta(&"select_fate") == -2, "fate_efficient + reservoir_efficient stack: Select your Fate costs 2 less Mana")

func _test_big_bang_row() -> void:
	var c: Combatant = _mk_seer()
	_check(is_equal_approx(c.big_bang_heal_divisor(), 6.0), "baseline Big Bang heals 1/6 of spin total")
	_check(c.big_bang_shield_duration_bonus() == 0, "baseline Big Bang: no shield-duration bonus")
	_check(not c.has_ability_talent(&"bigbang_curing"), "baseline Big Bang: no cleanse-on-heal")

	var c2: Combatant = _mk_seer()
	_check(c2.pick_ability_talent(&"ultimate", &"bigbang_deeper"), "picks bigbang_deeper")
	_check(is_equal_approx(c2.big_bang_heal_divisor(), 5.0), "bigbang_deeper: heals 1/5 of spin total (got %.3f)" % c2.big_bang_heal_divisor())

	var c3: Combatant = _mk_seer()
	_check(c3.pick_ability_talent(&"ultimate", &"bigbang_shielding"), "picks bigbang_shielding")
	_check(c3.big_bang_shield_duration_bonus() == 1, "bigbang_shielding: overflow shield lasts 1 turn longer")

	# bigbang_curing: replicate the exact two orchestrator primitives combat.gd's is_big_bang_active()
	# block chains (heal() then, if the talent is picked, cleanse()) — mirrors
	# tests/test_ability_talents_ranger.gd's own manual-replication convention.
	var c4: Combatant = _mk_seer()
	_check(c4.pick_ability_talent(&"ultimate", &"bigbang_curing"), "picks bigbang_curing")
	var ally: Combatant = _mk_seer()
	ally.max_hp = 100; ally.hp = 50
	var slow: Effect = EffectLibrary.make(&"slow")
	ally.attach_effect(slow)
	_check(ally.has_effect(&"slow"), "sanity: ally carries a debuff before the heal")
	ally.heal(10)
	if c4.has_ability_talent(&"bigbang_curing"):
		ally.cleanse()
	_check(not ally.has_effect(&"slow"), "bigbang_curing: the healed ally's debuff is cleansed")

	# Mutual exclusion within the ultimate row.
	var c5: Combatant = _mk_seer()
	_check(c5.pick_ability_talent(&"ultimate", &"bigbang_deeper"), "first pick on the ultimate row succeeds")
	_check(not c5.pick_ability_talent(&"ultimate", &"bigbang_shielding"), "a second pick on an already-filled row is rejected")

func _init() -> void:
	_test_options_for_shape()
	_test_select_fate_row()
	_test_hex_row()
	_test_foresight_row()
	_test_mana_surge_row()
	_test_arcane_reservoir_row()
	_test_big_bang_row()
	print(("SEER ABILITY TALENTS TEST PASSED" if _failures == 0 else "SEER ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
