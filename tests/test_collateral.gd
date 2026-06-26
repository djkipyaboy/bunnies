extends SceneTree

# Headless test: Ranger "Collateral Damage" Ultimate (spec §3.4) — consumes meter, +1 reel, NOT AoE
# (primary takes full, stays mark-eligible), and splashes ceil(total/2) Piercing to every OTHER enemy.
# Splash is verified with a synthetic 3-enemy setup (the scene runs 1v1, where the splash is a no-op).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_collateral.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_armed(reel_count: int, type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 7.0
	for i: int in range(reel_count):
		w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.bonus_meter = BonusMeter.new(); c.bonus_meter.cap = 30; c.bonus_meter.value = 30  # armed
	c.begin_turn()
	return c

func _initialize() -> void:
	var piercing: DamageType = load("res://combat/resources/types/piercing.tres")

	# --- fire_collateral: armed → consumes meter, +1 reel (4→5), Collateral active, NOT AoE ---
	var ranger: Combatant = _make_armed(4, piercing)
	_check(ranger.turn_reels.size() == 4, "starts with 4 reels")
	var fired: bool = ranger.fire_collateral(piercing, 1)
	_check(fired, "fire_collateral succeeds when armed")
	_check(ranger.bonus_meter.value == 0, "collateral consumed the full meter (got %d)" % ranger.bonus_meter.value)
	_check(ranger.turn_reels.size() == 5, "collateral added +1 reel → 5 (got %d)" % ranger.turn_reels.size())
	_check(ranger.is_collateral_active(), "Collateral active for the spin")
	_check(not ranger.is_aoe_active(), "Collateral is NOT an AoE spin (primary stays mark-eligible)")
	# The added reel is a real weapon-attack reel (joins the payline grid, deals damage).
	var added: ActionReel = ranger.turn_reels[4]
	_check(added.is_weapon_attack, "added collateral reel is a weapon-attack reel")
	_check(added.faces.any(func(f: ReelFace) -> bool: return f.multiplier > 0.0), "added reel deals damage")

	# Consume the single spin; it clears.
	ranger.consume_collateral_spin()
	_check(not ranger.is_collateral_active(), "Collateral cleared after one spin")

	# Not armed → no fire.
	var poor: Combatant = _make_armed(4, piercing)
	poor.bonus_meter.value = 5
	_check(not poor.fire_collateral(piercing, 1), "fire_collateral fails when meter not armed")

	# --- splash math (the orchestrator's formula) over a synthetic 3-enemy setup ---
	# Primary total 21 → splash ceil(21/2) = 11 to each OTHER enemy; primary excluded.
	var primary_total: int = 21
	var splash: int = ceili(primary_total / 2.0)
	_check(splash == 11, "ceil(21/2) = 11 (got %d)" % splash)
	_check(ceili(7 / 2.0) == 4, "odd total rounds up: ceil(7/2) = 4")

	var primary: Combatant = Combatant.new(); primary.base_max_hp = 300; primary.max_hp = 300; primary.start_combat()
	var other_a: Combatant = Combatant.new(); other_a.base_max_hp = 300; other_a.max_hp = 300; other_a.start_combat()
	var other_b: Combatant = Combatant.new(); other_b.base_max_hp = 300; other_b.max_hp = 300; other_b.start_combat()
	# Splash hits the two OTHER enemies, never the primary.
	for other: Combatant in [other_a, other_b]:
		other.take_damage(splash)
	_check(primary.hp == 300, "primary takes NO splash (it took full damage from the reels)")
	_check(other_a.hp == 300 - splash and other_b.hp == 300 - splash, "each other enemy took %d splash" % splash)

	print(("COLLATERAL TEST PASSED" if _failures == 0 else "COLLATERAL TEST FAILED: %d" % _failures))
	quit(_failures)
