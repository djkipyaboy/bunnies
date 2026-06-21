extends SceneTree

# Headless unit test for Stats/Gear + Combatant stat integration (DESIGN spec 2026-06-20).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stats.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _stats(mi: int, fi: int, vi: int, fo: int, gr: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr
	return s

func _initialize() -> void:
	# plus() sums fields.
	var sum: Stats = _stats(1,2,3,4,5).plus(_stats(10,20,30,40,50))
	_check(sum.might == 11 and sum.finesse == 22 and sum.vigor == 33 and sum.focus == 44 and sum.grit == 55, "Stats.plus sums fields")

	# effective_stats = base + each gear's bonuses.
	var c: Combatant = Combatant.new()
	c.base_stats = _stats(1,0,0,0,0)
	var jerkin: Gear = Gear.new()
	jerkin.slot = Gear.Slot.ARMOR
	jerkin.stat_bonuses = _stats(3,2,0,0,0)
	c.gear = [jerkin]
	var eff: Stats = c.effective_stats()
	_check(eff.might == 4 and eff.finesse == 2, "effective = base Might 1 + jerkin Might 3 = 4, Finesse 2 (got M%d F%d)" % [eff.might, eff.finesse])

	# apply_stats derives max_hp / max_stamina / meter.floor from effective stats.
	var d: Combatant = Combatant.new()
	d.base_max_hp = 40; d.base_max_stamina = 5; d.base_meter_floor = 3
	d.resource_pool = ResourcePool.new(); d.resource_pool.stamina = 5
	d.bonus_meter = BonusMeter.new()
	d.base_stats = _stats(0,0,2,1,4)  # vigor 2, focus 1, grit 4
	d.apply_stats()
	_check(d.max_hp == 42, "max_hp = base 40 + vigor 2 = 42 (got %d)" % d.max_hp)
	_check(d.resource_pool.max_stamina == 6, "max_stamina = base 5 + focus 1 = 6 (got %d)" % d.resource_pool.max_stamina)
	_check(d.bonus_meter.floor == 7, "meter floor = base 3 + grit 4 = 7 (got %d)" % d.bonus_meter.floor)

	# null base_stats / no gear -> all zeros (safe).
	var e: Combatant = Combatant.new()
	var z: Stats = e.effective_stats()
	_check(z.might == 0 and z.finesse == 0, "no base/gear -> zero stats")

	# --- Luck: plus() includes luck; apply_luck adds crit faces to each weapon reel ---
	var ls: Stats = Stats.new(); ls.luck = 2
	_check(ls.plus(Stats.new()).luck == 2, "Stats.plus sums luck")
	var slashing2: DamageType = load("res://combat/resources/types/slashing.tres")
	var lw: Weapon = Weapon.new()
	lw.base_damage = 10.0
	lw.reels.append(ActionReel.make_default(slashing2))
	var base_crit: int = 0
	for f: ReelFace in lw.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: base_crit += 1
	var lc: Combatant = Combatant.new()
	lc.weapon = lw
	lc.base_stats = ls   # luck 2
	lc.apply_luck()
	var new_crit: int = 0
	for f: ReelFace in lc.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: new_crit += 1
	_check(new_crit == base_crit + 2, "apply_luck adds 2 crit faces (Luck 2): %d -> %d" % [base_crit, new_crit])
	# Idempotency note: apply_luck is called ONCE at setup; not re-applied.

	print(("STATS TEST PASSED" if _failures == 0 else "STATS TEST FAILED: %d" % _failures))
	quit(_failures)
