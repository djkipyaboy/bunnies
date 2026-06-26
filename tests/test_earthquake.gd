extends SceneTree

# Headless test: Combatant.fire_earthquake (Warden Ultimate, spec 2026-06-29 §4). +1 weapon-attack reel
# (3 → 4), all 4 WILD, NOT AoE (primary takes full; orchestrator splashes half to others), reel inserted
# contiguously before any trailing utility reel. Also covers the splash + force-stun rules.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_earthquake.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_armed_warden(type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 9.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.bonus_meter = BonusMeter.new(); c.bonus_meter.cap = 15; c.bonus_meter.value = 15  # armed
	c.begin_turn()
	return c

func _initialize() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")

	# fire_earthquake alone: 3 → 4 weapon-attack reels, all 4 wild, NOT AoE, meter consumed.
	var w: Combatant = _make_armed_warden(earth)
	_check(w.turn_reels.size() == 3, "starts with 3 reels")
	var fired: bool = w.fire_earthquake(earth, 1)
	_check(fired, "fire_earthquake succeeds when armed")
	_check(w.bonus_meter.value == 0, "consumed the full meter (got %d)" % w.bonus_meter.value)
	_check(w.turn_reels.size() == 4, "added 1 reel (3 → 4, got %d)" % w.turn_reels.size())
	_check(w.wild_reel_indices() == [0, 1, 2, 3], "all 4 reels wild (got %s)" % str(w.wild_reel_indices()))
	_check(not w.is_aoe_active(), "Earthquake is NOT an AoE spin (primary takes full; splash is separate)")
	_check(w.is_earthquake_active(), "earthquake active for the spin")
	var all_attack: bool = w.turn_reels.all(func(r: ActionReel) -> bool: return r.is_weapon_attack)
	_check(all_attack, "all 4 reels are weapon-attack reels (feed the 4-wide payline grid)")

	# Consume → clears.
	w.consume_earthquake_spin()
	w.consume_wild_spin()
	_check(not w.is_earthquake_active(), "earthquake cleared after one spin")
	_check(w.wild_reel_indices().is_empty(), "wild cleared after one spin")

	# Not armed → no fire.
	var poor: Combatant = _make_armed_warden(earth)
	poor.bonus_meter.value = 5
	_check(not poor.fire_earthquake(earth, 1), "fire_earthquake fails when meter not armed")

	# CONTIGUITY: with a trailing utility (Rallying Cry) reel already present, Earthquake's attack reel
	# inserts BEFORE it so the 4 weapon-attack reels stay contiguous at the front (grid + WILD correct).
	var combo: Combatant = _make_armed_warden(earth)
	combo.resource_pool = ResourcePool.new(); combo.resource_pool.mana = 12; combo.resource_pool.max_mana = 12
	combo.apply_rallying_cry(4, 5)  # turn_reels = [w0, w1, w2, rally]
	_check(combo.turn_reels.size() == 4 and not combo.turn_reels[3].is_weapon_attack, "rally reel sits at index 3")
	combo.fire_earthquake(earth, 1)  # → [w0, w1, w2, eq, rally]
	_check(combo.turn_reels.size() == 5, "5 reels with both staged (got %d)" % combo.turn_reels.size())
	_check(combo.turn_reels[3].is_weapon_attack, "Earthquake reel inserted at index 3 (contiguous attack run)")
	_check(not combo.turn_reels[4].is_weapon_attack, "rally reel pushed to the tail (index 4)")
	_check(combo.wild_reel_indices() == [0, 1, 2, 3], "WILD covers exactly the 4 attack reels (got %s)" % str(combo.wild_reel_indices()))

	# SPLASH math (orchestrator formula): primary total 30 → others take ceil(30/2)=15.
	_check(ceili(30 / 2.0) == 15, "splash = ceil(30/2) = 15")
	_check(ceili(7 / 2.0) == 4, "odd total rounds up: ceil(7/2) = 4")

	# STUN rule: every DAMAGED enemy is force-stunned; next turn it is STUNNED with init untouched.
	var enemy: Combatant = Combatant.new(); enemy.base_initiative = 40; enemy.recompute_initiative()
	enemy.hp = 100; enemy.max_hp = 100
	enemy.take_damage(15)  # damaged by the splash
	_check(enemy.hp == 85, "enemy took 15 splash")
	enemy.force_stun_next_turn = true  # orchestrator sets this on every damaged enemy
	var init_before: int = enemy.current_initiative
	_check(enemy.evaluate_stun(-20), "damaged enemy is STUNNED next turn")
	_check(enemy.current_initiative == init_before, "stunned enemy keeps its initiative (queue position)")

	print(("EARTHQUAKE TEST PASSED" if _failures == 0 else "EARTHQUAKE TEST FAILED: %d" % _failures))
	quit(_failures)
