extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Earned/available across the L2/4/6/8/10 cadence (spec 2026-07-24 §2).
	var c: Combatant = Combatant.new()
	c.level = 1
	_check(c.universal_points_earned() == 0, "L1: 0 universal points earned")
	c.level = 2
	_check(c.universal_points_earned() == 1, "L2: 1st milestone reached")
	c.level = 3
	_check(c.universal_points_earned() == 1, "L3: still 1 (odd levels grant nothing)")
	c.level = 4
	_check(c.universal_points_earned() == 2, "L4: 2nd milestone reached")
	c.level = 6
	_check(c.universal_points_earned() == 3, "L6: 3rd milestone reached")
	c.level = 8
	_check(c.universal_points_earned() == 4, "L8: 4th milestone reached")
	c.level = 10
	_check(c.universal_points_earned() == 5, "L10: all 5 milestones reached")
	_check(c.universal_points_available() == 5, "L10, none spent: 5 available")

	# One-time-pick enforcement.
	_check(c.pick_talent_perk(&"vigor_boost"), "picking an unpicked perk succeeds")
	_check(c.universal_points_available() == 4, "one point spent")
	_check(not c.pick_talent_perk(&"vigor_boost"), "picking the SAME perk again is rejected")
	_check(c.universal_points_available() == 4, "rejected pick spends nothing")
	_check(not c.pick_talent_perk(&"does_not_exist"), "picking an unknown perk id is rejected")

	# Flat stat perk applies through effective_stats().
	_check(c.effective_stats().vigor == 2, "vigor_boost grants +2 Vigor via effective_stats()")

	# Unpick refunds the point.
	_check(c.unpick_talent_perk(&"vigor_boost"), "unpicking a picked perk succeeds")
	_check(c.universal_points_available() == 5, "unpicking refunds the point")
	_check(c.effective_stats().vigor == 0, "unpicking vigor_boost removes its bonus")
	_check(not c.unpick_talent_perk(&"vigor_boost"), "unpicking an unpicked perk is rejected")

	# Can't pick past the earned total.
	var poor_c: Combatant = Combatant.new()
	poor_c.level = 2
	_check(poor_c.pick_talent_perk(&"might_boost"), "1st pick at L2 succeeds")
	_check(not poor_c.pick_talent_perk(&"finesse_boost"), "2nd pick at L2 (only 1 point earned) is rejected")

	# Bespoke (non-stat) universal perks.
	var sr: Combatant = Combatant.new()
	sr.level = 2
	sr.pick_talent_perk(&"sharp_reflexes")
	sr.recompute_initiative()
	_check(sr.current_initiative == 5, "sharp_reflexes: +5 flat Initiative")

	var ts: Combatant = Combatant.new()
	ts.level = 2
	ts.pick_talent_perk(&"thick_skin")
	_check(is_equal_approx(ts.incoming_damage_multiplier(), 0.95), "thick_skin: -5% incoming damage")

	var bh: Combatant = Combatant.new()
	bh.level = 2
	bh.pick_talent_perk(&"battle_hardened")
	_check(is_equal_approx(bh.dot_damage_multiplier(), 0.9), "battle_hardened: -10% incoming DoT damage")

	var dr_stamina: Combatant = Combatant.new()
	dr_stamina.level = 2
	dr_stamina.base_max_stamina = 5
	dr_stamina.resource_pool = ResourcePool.new()
	dr_stamina.apply_stats()
	var before_stamina: int = dr_stamina.resource_pool.max_stamina
	dr_stamina.pick_talent_perk(&"deep_reserves")
	_check(dr_stamina.resource_pool.max_stamina == before_stamina + 3, "deep_reserves: +3 max Stamina for a Stamina-rail character")

	var dr_mana: Combatant = Combatant.new()
	dr_mana.level = 2
	dr_mana.base_max_mana = 9
	dr_mana.resource_pool = ResourcePool.new()
	dr_mana.apply_stats()
	var before_mana: int = dr_mana.resource_pool.max_mana
	dr_mana.pick_talent_perk(&"deep_reserves")
	_check(dr_mana.resource_pool.max_mana == before_mana + 3, "deep_reserves: +3 max Mana for a Mana-rail character")

	quit()
