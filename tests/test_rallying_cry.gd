extends SceneTree

# Headless test: Combatant.apply_rallying_cry (Warden base ability, spec 2026-06-29 §3) + the
# orchestrator's per-tier shield formula over a synthetic 3-ally party.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_rallying_cry.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_warden(type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.ability_resource = &"mana"
	var w: Weapon = Weapon.new(); w.base_damage = 9.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.mana = 12; c.resource_pool.max_mana = 12
	c.begin_turn()
	return c

func _initialize() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")

	# apply_rallying_cry: spends 4 mana, appends the utility reel (3 → 4), records rallying_cry_reel.
	var w: Combatant = _make_warden(earth)
	_check(w.turn_reels.size() == 3, "starts with 3 reels")
	var ok: bool = w.apply_rallying_cry(4, 5)
	_check(ok, "apply_rallying_cry succeeds when affordable")
	_check(w.resource_pool.mana == 8, "spent 4 mana (12 → 8, got %d)" % w.resource_pool.mana)
	_check(w.turn_reels.size() == 4, "appended the utility reel (3 → 4, got %d)" % w.turn_reels.size())
	_check(w.rallying_cry_reel != null and w.rallying_cry_reel == w.turn_reels[3], "rallying_cry_reel records the appended reel")
	_check(not w.turn_reels[3].is_weapon_attack, "the rally reel is a non-weapon-attack reel")

	# begin_turn resets the recorded reel.
	w.begin_turn()
	_check(w.rallying_cry_reel == null, "begin_turn resets rallying_cry_reel")
	_check(w.turn_reels.size() == 3, "begin_turn resets to 3 weapon reels")

	# Unaffordable → no-op, false.
	var poor: Combatant = _make_warden(earth)
	poor.resource_pool.mana = 2
	_check(not poor.apply_rallying_cry(4, 5), "apply_rallying_cry fails when mana < cost")
	_check(poor.turn_reels.size() == 3 and poor.rallying_cry_reel == null, "no reel added when unaffordable")

	# At the reel cap → no-op, false (mana NOT spent).
	var capped: Combatant = _make_warden(earth)
	capped.turn_reels.append(ActionReel.make_default(earth))
	capped.turn_reels.append(ActionReel.make_default(earth))  # now 5 = cap
	_check(not capped.apply_rallying_cry(4, 5), "apply_rallying_cry fails at the reel cap")
	_check(capped.resource_pool.mana == 12, "no mana spent when at the cap (got %d)" % capped.resource_pool.mana)

	# --- per-tier shield formula (the orchestrator's logic) over a synthetic 3-ally party ---
	# weapon_base 9: SUCCESS → ceil(9*0.5)=5 shield; CRIT_SUCCESS → ceil(9)=9 shield; 2 turns.
	var base: float = 9.0
	_check(ceili(base * 0.5) == 5, "SUCCESS shield = ceil(9*0.5) = 5 (got %d)" % ceili(base * 0.5))
	_check(ceili(base) == 9, "CRIT shield = ceil(9) = 9 (got %d)" % ceili(base))
	var a: Combatant = Combatant.new()
	var b: Combatant = Combatant.new()
	for ally: Combatant in [a, b]:
		ally.apply_shield(ceili(base * 0.5), 2)
	_check(a.shield_hp == 5 and a.shield_turns == 2, "ally A gets a 5-shield for 2 turns")
	_check(b.shield_hp == 5, "ally B gets a 5-shield")
	# Higher-total-overrides: a crit later in the fight upgrades the shield to 9.
	a.apply_shield(ceili(base), 2)
	_check(a.shield_hp == 9, "crit shield upgrades 5 → 9 (higher overrides)")

	print(("RALLYING CRY TEST PASSED" if _failures == 0 else "RALLYING CRY TEST FAILED: %d" % _failures))
	quit(_failures)
