extends SceneTree

# Headless test for the STUNNED condition + anti-lock + d100 gate split (DESIGN spec 2026-06-20).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_stun.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(init: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.base_initiative = init
	c.recompute_initiative()
	return c

func _initialize() -> void:
	# Below threshold + not stunned last turn -> STUNNED.
	var a: Combatant = _mk(-25)
	_check(a.evaluate_stun(-20), "init -25 (< -20), not immune -> STUNNED")
	_check(a.stunned_this_turn, "stunned_this_turn set")

	# At/above threshold -> not stunned.
	var b: Combatant = _mk(-10)
	_check(not b.evaluate_stun(-20), "init -10 (>= -20) -> not stunned")
	var b2: Combatant = _mk(-20)
	_check(not b2.evaluate_stun(-20), "init -20 (not strictly below) -> not stunned")

	# Anti-lock: immune if stunned last turn, even at deep negative.
	var c: Combatant = _mk(-50)
	c.stunned_last_turn = true
	_check(not c.evaluate_stun(-20), "immune when stunned_last_turn (init -50)")

	# Lifecycle over 3 turns of deep-negative init: stun -> immune -> stun.
	var d: Combatant = _mk(-40)
	_check(d.evaluate_stun(-20), "turn 1: STUNNED")
	d.on_end()
	_check(d.stunned_last_turn and not d.stunned_this_turn, "turn 1 end: last=true, this reset")
	_check(not d.evaluate_stun(-20), "turn 2: immune (was stunned)")
	d.on_end()
	_check(not d.stunned_last_turn, "turn 2 end: last=false (this turn wasn't stunned)")
	_check(d.evaluate_stun(-20), "turn 3: STUNNED again (anti-lock cap = every other turn)")

	# d100 gate split: 01-50 lose (false), 51-100 recover (true).
	_check(not Combatant.stun_check_passed(1), "roll 1 -> lose")
	_check(not Combatant.stun_check_passed(50), "roll 50 -> lose (boundary)")
	_check(Combatant.stun_check_passed(51), "roll 51 -> recover (boundary)")
	_check(Combatant.stun_check_passed(100), "roll 100 -> recover")

	# TurnManager.roll_d100 in range 1..100.
	var tm: TurnManager = TurnManager.new()
	var out_of_range: int = 0
	for i: int in range(200):
		var r: int = tm.roll_d100()
		if r < 1 or r > 100: out_of_range += 1
	_check(out_of_range == 0, "roll_d100 in 1..100 (out: %d)" % out_of_range)

	print(("STUN TEST PASSED" if _failures == 0 else "STUN TEST FAILED: %d" % _failures))
	quit(_failures)
