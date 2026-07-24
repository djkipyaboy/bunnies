extends SceneTree

# Headless test: the Vanguard's 18 Ability Talent options (Task 16) — one row of 3 mutually-
# exclusive picks per Vanguard ability (Heft / Bloodwrath / Quake Slam / Mountain Stance / Bulwark /
# Rampage). Exercises AbilityTalentLibrary.options_for(&"vanguard", row_id), pick_ability_talent()/
# has_ability_talent(), the cost/cooldown-delta dispatch methods, and the reel-instance-scoped
# mechanisms slam_deeper/slam_heavier/rampage_deeper use INSTEAD of the generic per-rider-id talent
# hooks (see this task's Implementation note: Vanguard's own Crushing weapon shares Quake Slam's
# &"slow" rider id, so those hooks can't distinguish "Quake Slam's hit" from an ordinary weapon
# crit for this class).
#
# Slowing Rampage's ACTUAL on-hit attach lives in combat.gd's _apply_attack() — orchestrator-level,
# requires a running Combat scene — and is NOT headlessly tested here, consistent with this
# codebase's own documented precedent (tests/test_ability_talents_warrior.gd's header comment on
# Bleeding Wild). This test instead proves the precondition state combat.gd's wiring reads.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_vanguard.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier:
			n += 1
	return n

func _empowered_magnitude(c: Combatant) -> float:
	var e: Effect = c._find_effect(&"empowered")
	return e.magnitude if e != null else -1.0

func _empowered_duration(c: Combatant) -> int:
	var e: Effect = c._find_effect(&"empowered")
	return e.duration if e != null else -1

func _mk_vanguard() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"vanguard").build_combatant(true)
	c.level = Combatant.MAX_LEVEL  # unlocks every talent row (5/6/7/8/9/10)
	c.resource_pool.stamina = c.resource_pool.max_stamina
	c.begin_turn()  # populates turn_reels from the 2-reel Crushing War Hammer
	return c

func _test_options_for_shape() -> void:
	var rows: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
	var all_ids: Array[StringName] = [
		&"heft_reinforced", &"heft_guarding", &"heft_efficient",
		&"wrath_deeper", &"wrath_lasting", &"wrath_efficient",
		&"slam_deeper", &"slam_heavier", &"slam_efficient",
		&"stance_deeper", &"stance_thorned", &"stance_swift",
		&"bulwark_deeper", &"bulwark_wider", &"bulwark_thorned",
		&"rampage_deeper", &"rampage_slowing", &"rampage_lasting",
	]
	var seen: Array[StringName] = []
	for row: StringName in rows:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"vanguard", row)
		_check(opts.size() == 3, "Vanguard row %s has exactly 3 options (got %d)" % [row, opts.size()])
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "option %s reports its own row_id (%s)" % [o.id, row])
			_check(o.display_name != "" and o.description != "", "option %s has a non-empty display_name/description" % o.id)
			seen.append(o.id)
	for id: StringName in all_ids:
		_check(id in seen, "option %s is present in AbilityTalentLibrary.options_for(&vanguard, ...)" % id)

func _test_heft_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cost_delta(&"heft") == 0, "no Heft cost delta with nothing picked")
	_check(c.pick_ability_talent(&"base_ability", &"heft_efficient"), "picks heft_efficient")
	_check(c.ability_talent_cost_delta(&"heft") == -1, "heft_efficient: Heft costs 1 less Stamina")

	var c2: Combatant = _mk_vanguard()
	_check(c2.pick_ability_talent(&"base_ability", &"heft_reinforced"), "picks heft_reinforced")
	_check(c2.apply_heft(2), "casts Heft (reinforced)")
	var reel: ActionReel = c2.turn_reels[0]
	_check(_count(reel, ReelFace.ResultTier.NEUTRAL) == 1, "heft_reinforced: 1 NEUTRAL face converted (1 left, got %d)" % _count(reel, ReelFace.ResultTier.NEUTRAL))
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 8, "heft_reinforced: SUCCESS count is 8 (2 base misses + crit-fail + 1 neutral, got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))

	var c3: Combatant = _mk_vanguard()
	_check(c3.apply_heft(2), "casts Heft (baseline)")
	var reel3: ActionReel = c3.turn_reels[0]
	_check(_count(reel3, ReelFace.ResultTier.NEUTRAL) == 2, "baseline Heft leaves both NEUTRAL faces untouched (got %d)" % _count(reel3, ReelFace.ResultTier.NEUTRAL))

	var c4: Combatant = _mk_vanguard()
	_check(c4.pick_ability_talent(&"base_ability", &"heft_guarding"), "picks heft_guarding")
	_check(c4.apply_heft(2), "casts Heft (guarding)")
	var g: Effect = c4._find_effect(&"guarded")
	_check(g != null, "heft_guarding: Guarded attached")
	_check(is_equal_approx(g.magnitude, 0.9), "heft_guarding: Guarded magnitude 0.9 (got %.3f)" % g.magnitude)
	_check(g.duration == 1, "heft_guarding: 1-turn duration (got %d)" % g.duration)

	# Mutual exclusion: only 1 pick per row.
	var c5: Combatant = _mk_vanguard()
	_check(c5.pick_ability_talent(&"base_ability", &"heft_efficient"), "first pick on the Heft row succeeds")
	_check(not c5.pick_ability_talent(&"base_ability", &"heft_guarding"), "a second pick on an already-filled row is rejected (cap of 1/row)")
	_check(c5.has_ability_talent(&"heft_efficient"), "the row's original pick is still active")

func _test_bloodwrath_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cost_delta(&"bloodwrath") == 0, "no Bloodwrath cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l2", &"wrath_efficient"), "picks wrath_efficient")
	_check(c.ability_talent_cost_delta(&"bloodwrath") == -1, "wrath_efficient: Bloodwrath costs 1 less Stamina")

	var c2: Combatant = _mk_vanguard()
	c2.max_hp = 100; c2.hp = 10  # 90% missing
	_check(c2.pick_ability_talent(&"ability_l2", &"wrath_deeper"), "picks wrath_deeper")
	_check(c2.apply_bloodwrath(3), "casts Bloodwrath (deeper)")
	_check(is_equal_approx(_empowered_magnitude(c2), 1.60), "wrath_deeper: magnitude caps at 1.60 (90%% missing x1.2, capped 60%%, got %.3f)" % _empowered_magnitude(c2))

	var c3: Combatant = _mk_vanguard()
	c3.max_hp = 100; c3.hp = 10
	_check(c3.apply_bloodwrath(3), "casts Bloodwrath (baseline)")
	_check(is_equal_approx(_empowered_magnitude(c3), 1.50), "baseline Bloodwrath: magnitude caps at 1.50 (90%% missing, capped 50%%)")

	var c4: Combatant = _mk_vanguard()
	_check(c4.pick_ability_talent(&"ability_l2", &"wrath_lasting"), "picks wrath_lasting")
	_check(c4.apply_bloodwrath(3), "casts Bloodwrath (lasting)")
	_check(_empowered_duration(c4) == 3, "wrath_lasting: Empowered lasts 3 turns (got %d)" % _empowered_duration(c4))

	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.25), 0.25), "bloodwrath_bonus_pct(25%% missing), default scale/cap == 25%%")
	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.30, 1.2, 0.60), 0.36), "bloodwrath_bonus_pct(30%% missing, scale 1.2, cap 60%%) == 36%%")
	_check(is_equal_approx(Combatant.bloodwrath_bonus_pct(0.90, 1.2, 0.60), 0.60), "bloodwrath_bonus_pct(90%% missing, scale 1.2, cap 60%%) caps at 60%%")

func _test_quake_slam_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cost_delta(&"quake_slam") == 0, "no Quake Slam cost delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l3", &"slam_efficient"), "picks slam_efficient")
	_check(c.ability_talent_cost_delta(&"quake_slam") == -1, "slam_efficient: Quake Slam costs 1 less Stamina")

	var c2: Combatant = _mk_vanguard()
	_check(c2.pick_ability_talent(&"ability_l3", &"slam_deeper"), "picks slam_deeper")
	_check(c2.try_quake_slam(c2.weapon_type(), 4, 5), "casts Quake Slam (deeper)")
	var reel: ActionReel = c2.turn_reels[c2.turn_reels.size() - 1]
	var checked_success: bool = false
	var checked_crit: bool = false
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face.multiplier, 1.15), "slam_deeper: SUCCESS face multiplier is 1.15 (got %.3f)" % face.multiplier)
			checked_success = true
		elif face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			_check(is_equal_approx(face.multiplier, 2.30), "slam_deeper: CRIT_SUCCESS face multiplier is 2.30 (got %.3f)" % face.multiplier)
			checked_crit = true
	_check(checked_success and checked_crit, "sanity: both hit tiers exist on the spliced reel to check")

	var c3: Combatant = _mk_vanguard()
	_check(c3.pick_ability_talent(&"ability_l3", &"slam_heavier"), "picks slam_heavier")
	_check(c3.try_quake_slam(c3.weapon_type(), 4, 5), "casts Quake Slam (heavier)")
	var reel3: ActionReel = c3.turn_reels[c3.turn_reels.size() - 1]
	_check(reel3.talent_extra_rider_stack, "slam_heavier: the spliced reel is flagged for a 2nd rider stack")

	var c4: Combatant = _mk_vanguard()
	_check(c4.try_quake_slam(c4.weapon_type(), 4, 5), "casts Quake Slam (baseline)")
	var reel4: ActionReel = c4.turn_reels[c4.turn_reels.size() - 1]
	_check(not reel4.talent_extra_rider_stack, "baseline Quake Slam: no 2nd-stack flag")
	for face4: ReelFace in reel4.faces:
		if face4.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face4.multiplier, 1.0), "baseline Quake Slam: SUCCESS multiplier stays 1.0 (got %.3f)" % face4.multiplier)

func _test_mountain_stance_row() -> void:
	var c: Combatant = _mk_vanguard()
	_check(c.ability_talent_cooldown_delta(&"mountain_stance") == 0, "no Mountain Stance cooldown delta with nothing picked")
	_check(c.pick_ability_talent(&"ability_l4", &"stance_swift"), "picks stance_swift")
	_check(c.ability_talent_cooldown_delta(&"mountain_stance") == -1, "stance_swift: Mountain Stance cooldown is 1 less turn")

	# passive_ability_id cleared on c2/c3: _mk_vanguard() builds a real Vanguard whose L5 passive is
	# Bulwark (its own -15%/-25% incoming reduction above 50% HP, tested separately in
	# _test_bulwark_row), which would otherwise stack multiplicatively with Mountain Stance's own
	# Guarded here and make these checks read the WRONG combined number for what this row's own
	# talents actually contribute.
	var c2: Combatant = _mk_vanguard()
	c2.passive_ability_id = &""
	_check(c2.pick_ability_talent(&"ability_l4", &"stance_deeper"), "picks stance_deeper")
	_check(c2.apply_mountain_stance(5), "casts Mountain Stance (deeper)")
	_check(is_equal_approx(c2.incoming_damage_multiplier(), 0.4), "stance_deeper: incoming multiplier 0.4 (got %.3f)" % c2.incoming_damage_multiplier())

	var c3: Combatant = _mk_vanguard()
	c3.passive_ability_id = &""
	_check(c3.apply_mountain_stance(5), "casts Mountain Stance (baseline)")
	_check(is_equal_approx(c3.incoming_damage_multiplier(), 0.5), "baseline Mountain Stance: incoming multiplier 0.5")

	var c4: Combatant = _mk_vanguard()
	_check(c4.pick_ability_talent(&"ability_l4", &"stance_thorned"), "picks stance_thorned")
	_check(c4.apply_mountain_stance(5), "casts Mountain Stance (thorned)")
	_check(is_equal_approx(c4.thorns_pct(), 0.15), "stance_thorned: 15%% Thorns while Mountain Stance is up (got %.3f)" % c4.thorns_pct())

func _test_bulwark_row() -> void:
	var c: Combatant = _mk_vanguard()
	c.passive_ability_id = &"bulwark"
	c.max_hp = 100; c.hp = 51
	_check(is_equal_approx(c.passive_incoming_multiplier(), 0.85), "baseline Bulwark: -15% just above 50% HP")

	var c2: Combatant = _mk_vanguard()
	c2.passive_ability_id = &"bulwark"
	c2.max_hp = 100; c2.hp = 51
	_check(c2.pick_ability_talent(&"passive", &"bulwark_deeper"), "picks bulwark_deeper")
	_check(is_equal_approx(c2.passive_incoming_multiplier(), 0.75), "bulwark_deeper: -25%% just above 50%% HP (got %.3f)" % c2.passive_incoming_multiplier())

	# bulwark_wider: implemented literally to the approved 50%->60% number (see this task's
	# Implementation note re: the apparent "active more often" wording mismatch — flagged for the
	# player, not silently changed).
	var c3: Combatant = _mk_vanguard()
	c3.passive_ability_id = &"bulwark"
	c3.max_hp = 100; c3.hp = 55
	_check(is_equal_approx(c3.passive_incoming_multiplier(), 0.85), "sanity: 55%% HP is active under the baseline >50%% threshold")
	_check(c3.pick_ability_talent(&"passive", &"bulwark_wider"), "picks bulwark_wider")
	_check(is_equal_approx(c3.passive_incoming_multiplier(), 1.0), "bulwark_wider: 55%% HP no longer qualifies once the threshold moves to >60%% (see the task's Implementation note)")
	c3.hp = 65
	_check(is_equal_approx(c3.passive_incoming_multiplier(), 0.85), "bulwark_wider: -15%% still applies at 65%% HP (above the moved 60%% threshold)")

	var c4: Combatant = _mk_vanguard()
	c4.passive_ability_id = &"bulwark"
	c4.max_hp = 100; c4.hp = 51
	_check(is_equal_approx(c4.thorns_pct(), 0.0), "baseline Bulwark grants no Thorns")
	_check(c4.pick_ability_talent(&"passive", &"bulwark_thorned"), "picks bulwark_thorned")
	_check(is_equal_approx(c4.thorns_pct(), 0.10), "bulwark_thorned: 10%% Thorns while Bulwark is active (got %.3f)" % c4.thorns_pct())
	c4.hp = 50
	_check(is_equal_approx(c4.thorns_pct(), 0.0), "bulwark_thorned: no Thorns once Bulwark's own 50%% condition drops off")

func _test_rampage_row() -> void:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")

	var c: Combatant = _mk_vanguard()
	c.bonus_meter.value = c.bonus_meter.cap
	_check(c.fire_rampage(crushing, 2, 1), "fires Rampage (baseline)")
	_check(c.aoe_spins_remaining == 1, "baseline Rampage: 1 AoE spin (got %d)" % c.aoe_spins_remaining)

	var c2: Combatant = _mk_vanguard()
	c2.bonus_meter.value = c2.bonus_meter.cap
	_check(c2.pick_ability_talent(&"ultimate", &"rampage_deeper"), "picks rampage_deeper")
	_check(c2.fire_rampage(crushing, 2, 1), "fires Rampage (deeper)")
	var added: ActionReel = c2.turn_reels[c2.turn_reels.size() - 1]
	var checked: bool = false
	for face: ReelFace in added.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS:
			_check(is_equal_approx(face.multiplier, 1.15), "rampage_deeper: the added reel's SUCCESS multiplier is 1.15 (got %.3f)" % face.multiplier)
			checked = true
	_check(checked, "sanity: a SUCCESS face exists on the added reel to check")

	var c3: Combatant = _mk_vanguard()
	c3.bonus_meter.value = c3.bonus_meter.cap
	_check(c3.pick_ability_talent(&"ultimate", &"rampage_slowing"), "picks rampage_slowing")
	_check(c3.fire_rampage(crushing, 2, 1), "fires Rampage (slowing)")
	_check(c3.is_aoe_active(), "Rampage's AoE is active for combat.gd's rampage_slowing check to read")

	var c4: Combatant = _mk_vanguard()
	c4.bonus_meter.value = c4.bonus_meter.cap
	var plan: MainPhasePlan = MainPhasePlan.new(c4)
	_check(plan.ultimate_id == &"rampage", "sanity: Vanguard's Ultimate id is &rampage")
	plan.toggle_ultimate()
	_check(plan.fire_ultimate_staged, "Rampage ultimate stages when the meter is armed")
	plan.commit()
	_check(c4.aoe_spins_remaining == 1, "without Lasting Rampage, firing Rampage grants 1 AoE spin (got %d)" % c4.aoe_spins_remaining)

	var c5: Combatant = _mk_vanguard()
	c5.bonus_meter.value = c5.bonus_meter.cap
	_check(c5.pick_ability_talent(&"ultimate", &"rampage_lasting"), "picks rampage_lasting")
	var plan2: MainPhasePlan = MainPhasePlan.new(c5)
	plan2.toggle_ultimate()
	plan2.commit()
	_check(c5.aoe_spins_remaining == 2, "rampage_lasting: firing Rampage grants 2 AoE spins (got %d)" % c5.aoe_spins_remaining)

func _init() -> void:
	_test_options_for_shape()
	_test_heft_row()
	_test_bloodwrath_row()
	_test_quake_slam_row()
	_test_mountain_stance_row()
	_test_bulwark_row()
	_test_rampage_row()
	print(("VANGUARD ABILITY TALENTS TEST PASSED" if _failures == 0 else "VANGUARD ABILITY TALENTS TEST FAILED: %d" % _failures))
	quit(_failures)
