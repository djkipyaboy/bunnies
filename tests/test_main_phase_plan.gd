extends SceneTree

# Headless unit test for MainPhasePlan — staged Main-1 choices + preview, commit on SPIN.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_main_phase_plan.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_pc(stamina: int, meter_value: int) -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.weapon = w
	c.resource_pool = ResourcePool.new()
	c.resource_pool.max_stamina = 5
	c.resource_pool.stamina = stamina
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 10
	c.bonus_meter.value = meter_value
	c.begin_turn()  # seeds turn_reels from the weapon (3 reels)
	return c

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")

	# --- Fresh plan: nothing staged ---
	var c: Combatant = _mk_pc(3, 0)
	var plan: MainPhasePlan = MainPhasePlan.new(c, storm, 2, 5, 0, 2)
	_check(not plan.splice_staged and not plan.fire_ultimate_staged, "fresh plan stages nothing")
	_check(plan.preview_reels().size() == 3, "preview = 3 reels when nothing staged (got %d)" % plan.preview_reels().size())
	_check(plan.preview_stamina() == 3, "preview stamina = current when nothing staged (got %d)" % plan.preview_stamina())
	_check(not plan.will_consume_meter(), "no meter consumption when no ultimate staged")
	_check(plan.effective_wild_indices() == [], "no wild when nothing staged/active (got %s)" % str(plan.effective_wild_indices()))

	# --- Stage splice: preview grows, costs preview-only, NOTHING mutated ---
	plan.toggle_splice()
	_check(plan.splice_staged, "splice staged after toggle")
	_check(plan.preview_reels().size() == 4, "preview = 4 reels when splice staged (got %d)" % plan.preview_reels().size())
	_check(plan.preview_reels()[3].damage_type == storm, "previewed 4th reel is Storm-typed")
	_check(plan.preview_stamina() == 1, "preview stamina = 3 - 2 = 1 (got %d)" % plan.preview_stamina())
	_check(c.turn_reels.size() == 3, "PREVIEW DID NOT MUTATE turn_reels (got %d)" % c.turn_reels.size())
	_check(c.resource_pool.stamina == 3, "PREVIEW DID NOT SPEND stamina (got %d)" % c.resource_pool.stamina)

	# --- Un-stage splice reverts the preview ---
	plan.toggle_splice()
	_check(not plan.splice_staged and plan.preview_reels().size() == 3, "un-stage splice reverts preview")

	# --- Cannot stage splice when unaffordable ---
	var poor: Combatant = _mk_pc(1, 0)
	var plan_poor: MainPhasePlan = MainPhasePlan.new(poor, storm, 2, 5, 0, 2)
	plan_poor.toggle_splice()
	_check(not plan_poor.splice_staged, "splice not staged when unaffordable (1 < 2 STA)")

	# --- Cannot stage splice at the reel cap ---
	var capped: Combatant = _mk_pc(5, 0)
	capped.try_splice_reel(storm, 10.0, 0, 5)  # 3 -> 4
	capped.try_splice_reel(storm, 10.0, 0, 5)  # 4 -> 5 (cost 0 so stamina irrelevant)
	var plan_cap: MainPhasePlan = MainPhasePlan.new(capped, storm, 2, 5, 0, 2)
	plan_cap.toggle_splice()
	_check(not plan_cap.splice_staged, "splice not staged at 5-reel cap (turn_reels=%d)" % capped.turn_reels.size())

	# --- Ultimate: cannot stage unless armed ---
	var unarmed: Combatant = _mk_pc(3, 9)
	var plan_unarmed: MainPhasePlan = MainPhasePlan.new(unarmed, storm, 2, 5, 0, 2)
	plan_unarmed.toggle_ultimate()
	_check(not plan_unarmed.fire_ultimate_staged, "ultimate not staged below meter cap")

	var armed: Combatant = _mk_pc(3, 10)
	var plan_armed: MainPhasePlan = MainPhasePlan.new(armed, storm, 2, 5, 0, 2)
	plan_armed.toggle_ultimate()
	_check(plan_armed.fire_ultimate_staged, "ultimate staged when meter armed")
	_check(plan_armed.will_consume_meter(), "will_consume_meter true when ultimate staged")
	_check(plan_armed.effective_wild_indices() == [0, 1, 2], "staged fire -> all weapon reels wild [0,1,2] (got %s)" % str(plan_armed.effective_wild_indices()))
	_check(armed.bonus_meter.value == 10, "PREVIEW DID NOT CONSUME the meter (got %d)" % armed.bonus_meter.value)

	# --- effective_wild_indices reflects carryover even with nothing staged ---
	var carry: Combatant = _mk_pc(3, 10)
	carry.fire_sticky_wild(carry.weapon.reels.size(), 2)  # simulate a prior-turn commit; meter 0, all reels wild
	var plan_carry: MainPhasePlan = MainPhasePlan.new(carry, storm, 2, 5, 0, 2)
	_check(not plan_carry.fire_ultimate_staged, "carryover: nothing staged this turn")
	_check(plan_carry.effective_wild_indices() == [0, 1, 2], "carryover wild surfaces in preview (got %s)" % str(plan_carry.effective_wild_indices()))

	# --- commit: splice spends + appends ---
	var cs: Combatant = _mk_pc(3, 0)
	var pcs: MainPhasePlan = MainPhasePlan.new(cs, storm, 2, 5, 0, 2)
	pcs.toggle_splice()
	pcs.commit()
	_check(cs.turn_reels.size() == 4, "commit splice -> 4 reels (got %d)" % cs.turn_reels.size())
	_check(cs.resource_pool.stamina == 1, "commit splice spent 2 STA (got %d)" % cs.resource_pool.stamina)

	# --- commit: fire consumes meter + arms wild, never touches stamina ---
	var cf: Combatant = _mk_pc(4, 10)
	var pcf: MainPhasePlan = MainPhasePlan.new(cf, storm, 2, 5, 0, 2)
	pcf.toggle_ultimate()
	pcf.commit()
	_check(cf.bonus_meter.value == 0, "commit fire consumed the meter (got %d)" % cf.bonus_meter.value)
	_check(cf.wild_reel_indices() == [0, 1, 2], "commit fire armed all weapon reels (got %s)" % str(cf.wild_reel_indices()))
	_check(cf.resource_pool.stamina == 4, "commit fire did NOT spend stamina (got %d)" % cf.resource_pool.stamina)

	# --- commit: nothing staged is a no-op ---
	var cn: Combatant = _mk_pc(3, 10)
	var pcn: MainPhasePlan = MainPhasePlan.new(cn, storm, 2, 5, 0, 2)
	pcn.commit()
	_check(cn.turn_reels.size() == 3 and cn.resource_pool.stamina == 3 and cn.bonus_meter.value == 10, "empty commit is a no-op")

	print(("MAIN PHASE PLAN TEST PASSED" if _failures == 0 else "MAIN PHASE PLAN TEST FAILED: %d" % _failures))
	quit(_failures)
