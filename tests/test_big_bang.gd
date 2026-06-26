extends SceneTree

# Headless test: Seer "The Big Bang" Ultimate (spec 2026-06-27 §4) — consumes meter, tops the loadout to
# 4 crit-biased WILD reels, fires AoE (all enemies), then heals each ally ceil(total/6) with overflow → a
# 2-turn SHIELDED. AoE/heal-all is verified with a synthetic 3-ally setup (the scene runs 1v1).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_big_bang.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_armed_seer(type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 13.0
	for i: int in range(2):
		w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.bonus_meter = BonusMeter.new(); c.bonus_meter.cap = 15; c.bonus_meter.value = 15  # armed
	c.begin_turn()
	return c

func _initialize() -> void:
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")

	# --- fire_big_bang: armed → consume meter, top to 4 reels, all wild, AoE, big-bang active ---
	var seer: Combatant = _make_armed_seer(mystic)
	_check(seer.turn_reels.size() == 2, "Seer starts with 2 reels")
	var fired: bool = seer.fire_big_bang(mystic, 4, 1)
	_check(fired, "fire_big_bang succeeds when armed")
	_check(seer.bonus_meter.value == 0, "Big Bang consumed the full meter (got %d)" % seer.bonus_meter.value)
	_check(seer.turn_reels.size() == 4, "topped loadout to 4 reels (got %d)" % seer.turn_reels.size())
	var wilds: Array[int] = seer.wild_reel_indices()
	_check(wilds == [0, 1, 2, 3], "all 4 reels are wild (got %s)" % str(wilds))
	_check(seer.is_aoe_active(), "Big Bang is an AoE spin (hits all enemies)")
	_check(seer.is_big_bang_active(), "Big Bang active for the spin")
	for r: ActionReel in seer.turn_reels:
		_check(r.is_weapon_attack, "every Big Bang reel is a weapon-attack reel (joins paylines)")

	# Consume the single spin; aoe + wild + big-bang all clear.
	seer.consume_big_bang_spin()
	seer.consume_aoe_spin()
	seer.consume_wild_spin()
	_check(not seer.is_big_bang_active(), "Big Bang cleared after one spin")
	_check(not seer.is_aoe_active(), "AoE cleared after one spin")

	# --- not armed → no fire ---
	var poor: Combatant = _make_armed_seer(mystic)
	poor.bonus_meter.value = 5
	_check(not poor.fire_big_bang(mystic, 4, 1), "fire_big_bang fails when meter not armed")

	# --- already-4 loadout: top-up is a no-op count-wise (still 4) ---
	var wide: Combatant = _make_armed_seer(mystic)
	wide.turn_reels.append(ActionReel.make_default(mystic))
	wide.turn_reels.append(ActionReel.make_default(mystic))  # now 4
	_check(wide.fire_big_bang(mystic, 4, 1), "fire_big_bang fires at 4 reels already")
	_check(wide.turn_reels.size() == 4, "no extra reels added past the target (got %d)" % wide.turn_reels.size())

	# --- heal/shield math (the orchestrator's formula) over a synthetic 3-ally party ---
	# total damage 120 → heal ceil(120/6) = 20 to each ally; overflow → 2-turn shield.
	var total: int = 120
	var heal_amt: int = ceili(total / 6.0)
	_check(heal_amt == 20, "ceil(120/6) = 20 (got %d)" % heal_amt)
	_check(ceili(7 / 6.0) == 2, "odd total rounds up: ceil(7/6) = 2")

	# Ally A wounded (heals, no overflow); Ally B near-full (heals to full + shield from overflow);
	# Ally C full (all 20 overflow → 20 shield).
	var a: Combatant = Combatant.new(); a.base_max_hp = 300; a.max_hp = 300; a.hp = 250
	var b: Combatant = Combatant.new(); b.base_max_hp = 300; b.max_hp = 300; b.hp = 295
	var cc: Combatant = Combatant.new(); cc.base_max_hp = 300; cc.max_hp = 300; cc.hp = 300
	for ally: Combatant in [a, b, cc]:
		var overflow: int = ally.heal(heal_amt)
		if overflow > 0:
			ally.apply_shield(overflow, 2)
	_check(a.hp == 270 and a.shield_hp == 0, "wounded ally: 250 → 270, no shield")
	_check(b.hp == 300 and b.shield_hp == 15, "near-full ally: 295 → 300 with a 15 shield (got hp %d shield %d)" % [b.hp, b.shield_hp])
	_check(cc.hp == 300 and cc.shield_hp == 20, "full ally: all 20 overflow → 20 shield (got %d)" % cc.shield_hp)
	_check(b.shield_turns == 2, "shield lasts 2 turns (got %d)" % b.shield_turns)

	print(("BIG BANG TEST PASSED" if _failures == 0 else "BIG BANG TEST FAILED: %d" % _failures))
	quit(_failures)
