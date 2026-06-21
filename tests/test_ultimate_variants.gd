extends SceneTree

# Headless test: separated WILD Ultimates (Warrior 1-spin vs Skirmisher 2-spin) + the Vanguard
# Rampage↔Heft coupling (auto-toggle, free, locked) in MainPhasePlan.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ultimate_variants.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _pc(ability: StringName, ultimate: StringName, reels: int, type: DamageType, cap: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.ability_id = ability
	c.ultimate_id = ultimate
	var w: Weapon = Weapon.new(); w.base_damage = 10.0
	for i: int in range(reels): w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.stamina = 3; c.resource_pool.max_stamina = 5
	c.bonus_meter = BonusMeter.new(); c.bonus_meter.cap = 10; c.bonus_meter.value = 10  # armed
	c.begin_turn()
	return c

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")

	# Warrior &"wild": single-spin.
	var w: Combatant = _pc(&"rend", &"wild", 3, slashing, 10)
	var pw: MainPhasePlan = MainPhasePlan.new(w, 2, 5, 2)
	pw.toggle_ultimate()
	pw.commit()
	_check(w.sticky_wild_spins_remaining == 1, "Warrior wild = 1 spin (got %d)" % w.sticky_wild_spins_remaining)

	# Skirmisher &"sticky_wild": two spins.
	var s: Combatant = _pc(&"flurry", &"sticky_wild", 4, slashing, 10)
	var ps: MainPhasePlan = MainPhasePlan.new(s, 2, 5, 2)
	ps.toggle_ultimate()
	ps.commit()
	_check(s.sticky_wild_spins_remaining == 2, "Skirmisher sticky wild = 2 spins (got %d)" % s.sticky_wild_spins_remaining)

	# Vanguard rampage↔heft coupling.
	var v: Combatant = _pc(&"heft", &"rampage", 2, crushing, 10)
	var pv: MainPhasePlan = MainPhasePlan.new(v, 2, 5, 2)
	_check(not pv.ability_staged and not pv.ability_is_free(), "fresh Vanguard plan: heft not staged")
	pv.toggle_ultimate()
	_check(pv.fire_ultimate_staged and pv.ability_staged, "toggling Rampage auto-stages Heft")
	_check(pv.ability_is_free(), "coupled Heft is free")
	_check(pv.preview_stamina() == 3, "free Heft does not deduct Stamina in preview (got %d)" % pv.preview_stamina())
	_check(pv.preview_reels().size() == 3, "Rampage previews +1 reel (got %d)" % pv.preview_reels().size())
	# Manual ability toggle is a no-op while free (locked by Rampage).
	pv.toggle_ability()
	_check(pv.ability_staged, "toggle_ability ignored while Heft is locked-free")
	# Untoggle Rampage -> Heft untoggles too.
	pv.toggle_ultimate()
	_check(not pv.fire_ultimate_staged and not pv.ability_staged, "untoggling Rampage untoggles Heft")

	# Commit with Rampage staged: meter consumed, +1 reel, hefted, AoE, and NO stamina spent on heft.
	var v2: Combatant = _pc(&"heft", &"rampage", 2, crushing, 10)
	var pv2: MainPhasePlan = MainPhasePlan.new(v2, 2, 5, 2)
	pv2.toggle_ultimate()
	pv2.commit()
	_check(v2.bonus_meter.value == 0, "rampage consumed meter")
	_check(v2.turn_reels.size() == 3, "rampage +1 reel committed (got %d)" % v2.turn_reels.size())
	_check(v2.is_aoe_active(), "rampage AoE active after commit")
	_check(v2.resource_pool.stamina == 3, "no Stamina spent on the free Heft (got %d)" % v2.resource_pool.stamina)

	print(("ULTIMATE VARIANTS TEST PASSED" if _failures == 0 else "ULTIMATE VARIANTS TEST FAILED: %d" % _failures))
	quit(_failures)
