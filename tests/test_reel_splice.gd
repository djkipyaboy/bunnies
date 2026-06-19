extends SceneTree

# Headless test: Main-1 reel splice is additive, costs Stamina, and respects the 5-reel band.
# Run: Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_reel_splice.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_pc(stamina: int) -> Combatant:
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
	return c

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")

	# --- begin_turn copies the weapon loadout (does not alias it) ---
	var c: Combatant = _mk_pc(3)
	c.begin_turn()
	_check(c.turn_reels.size() == 3, "begin_turn -> 3 turn reels (got %d)" % c.turn_reels.size())

	# --- splice appends one Storm reel and costs 2 Stamina ---
	var ok: bool = c.try_splice_reel(storm, c.weapon.base_damage, 2, 5)
	_check(ok, "splice succeeds with 3 stamina")
	_check(c.turn_reels.size() == 4, "splice -> 4 turn reels (got %d)" % c.turn_reels.size())
	_check(c.turn_reels[3].damage_type == storm, "spliced reel is Storm-typed")
	_check(c.resource_pool.stamina == 1, "splice cost 2 stamina (3 -> %d)" % c.resource_pool.stamina)
	_check(c.weapon.reels.size() == 3, "weapon loadout untouched (additive only, got %d)" % c.weapon.reels.size())

	# --- second splice refused: cannot afford (1 < 2), no mutation ---
	var ok2: bool = c.try_splice_reel(storm, c.weapon.base_damage, 2, 5)
	_check(not ok2, "second splice refused at 1 stamina")
	_check(c.turn_reels.size() == 4, "no reel added on refused splice (got %d)" % c.turn_reels.size())
	_check(c.resource_pool.stamina == 1, "stamina unchanged on refused splice (got %d)" % c.resource_pool.stamina)

	# --- band ceiling: cannot exceed 5 reels even with stamina to spare ---
	var c2: Combatant = _mk_pc(5)
	c2.begin_turn()
	_check(c2.try_splice_reel(storm, 10.0, 1, 5), "splice 4th reel ok")
	_check(c2.try_splice_reel(storm, 10.0, 1, 5), "splice 5th reel ok")
	_check(not c2.try_splice_reel(storm, 10.0, 1, 5), "6th splice refused at 5-reel cap")
	_check(c2.turn_reels.size() == 5, "capped at 5 reels (got %d)" % c2.turn_reels.size())

	# --- next turn resets the loadout (splice is this-turn-only) ---
	c.begin_turn()
	_check(c.turn_reels.size() == 3, "begin_turn resets to 3 (got %d)" % c.turn_reels.size())

	print(("REEL SPLICE TEST PASSED" if _failures == 0 else "REEL SPLICE TEST FAILED: %d" % _failures))
	quit(_failures)
