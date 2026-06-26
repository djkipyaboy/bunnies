extends SceneTree

# Headless test: force_stun_next_turn (Warden Earthquake stun, spec 2026-06-29 §4.3). A forced stun
# triggers STUNNED next turn WITHOUT altering current_initiative (queue position preserved), bypasses
# the anti-lock, is one-shot (consumed), and routes the existing d100 gate.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_force_stun.gd

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
	# Forced stun on a combatant whose initiative is WELL ABOVE the threshold → still STUNNED.
	var a: Combatant = _mk(50)
	a.force_stun_next_turn = true
	var init_before: int = a.current_initiative
	_check(a.evaluate_stun(-20), "forced stun → STUNNED even at init 50 (above threshold)")
	_check(a.current_initiative == init_before, "initiative UNCHANGED by the forced stun (queue preserved)")
	_check(not a.force_stun_next_turn, "force flag is consumed (one-shot)")

	# Forced stun BYPASSES the anti-lock (stunned last turn would normally grant immunity).
	var b: Combatant = _mk(50)
	b.stunned_last_turn = true
	b.force_stun_next_turn = true
	_check(b.evaluate_stun(-20), "forced stun bypasses the anti-lock (lands despite stunned_last_turn)")

	# Without the flag, a high-initiative combatant is NOT stunned (regression: normal path intact).
	var c: Combatant = _mk(50)
	_check(not c.evaluate_stun(-20), "no forced stun + high init → not stunned")

	# Init-based stun still respects the anti-lock (unchanged behavior).
	var d: Combatant = _mk(-50)
	d.stunned_last_turn = true
	_check(not d.evaluate_stun(-20), "init-based stun still immune when stunned_last_turn")

	print(("FORCE STUN TEST PASSED" if _failures == 0 else "FORCE STUN TEST FAILED: %d" % _failures))
	quit(_failures)
