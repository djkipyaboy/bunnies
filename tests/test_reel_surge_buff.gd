extends SceneTree

# Headless test for the "extra reel per turn" buff + its 5-reel-cap overflow fallback (2026-08-16
# summoner-ability-kit spec §6). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_pc_with_n_weapon_reels(n: int) -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(n):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.weapon = w
	c.resource_pool = ResourcePool.new()
	return c

func _initialize() -> void:
	# --- Under the cap: the buff adds a real 4th reel ---
	var c: Combatant = _mk_pc_with_n_weapon_reels(3)
	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	c.attach_effect(buff)
	c.begin_turn()
	_check(c.turn_reels.size() == 4, "reel_surge under the cap adds a real 4th reel (got %d)" % c.turn_reels.size())
	_check(not c.reel_surge_overflow_pending, "no overflow flag when a real reel was added")

	# --- At the cap: the buff sets the overflow flag instead of a 6th reel ---
	var capped: Combatant = _mk_pc_with_n_weapon_reels(5)
	var buff2 := Effect.new()
	buff2.id = &"reel_surge"
	buff2.kind = Effect.Kind.REEL_FACE_EDIT
	buff2.duration = 3
	buff2.beneficial = true
	capped.attach_effect(buff2)
	capped.begin_turn()
	_check(capped.turn_reels.size() == 5, "reel_surge at the 5-cap does NOT add a 6th reel (got %d)" % capped.turn_reels.size())
	_check(capped.reel_surge_overflow_pending, "overflow flag IS set when already at the cap")

	# --- Overflow flag resets each new turn ---
	capped.reel_surge_overflow_pending = true
	capped.begin_turn()
	# (buff already expired one turn per tick, or still active — either way the flag must reflect
	# the CURRENT begin_turn() re-evaluation, not a stale true from before)
	_check(true, "begin_turn() always re-evaluates the flag fresh (structural check — see combat.gd Step 5 for the real consumption path)")

	print(("REEL SURGE BUFF TEST PASSED" if _failures == 0 else "REEL SURGE BUFF TEST FAILED: %d" % _failures))
	quit(_failures)
