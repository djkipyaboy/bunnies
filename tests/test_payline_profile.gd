extends SceneTree

# Headless: CombatResolver.evaluate_paylines_profile dispatches whole-line vs left-aligned scoring and
# rebuilds last_grid. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_payline_profile.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	var r: CombatResolver = CombatResolver.new()
	var reels: Array[ActionReel] = []
	for i in range(4): reels.append(ActionReel.make_default(storm))
	var attacks: Array[CombatResolver.AttackResult] = []
	for rr: ActionReel in reels:
		attacks.append(r.reresolve_reel(rr, 6.0, null, 0))

	# left_align path runs against the casino lines and rebuilds the grid.
	var casino: Array = PaylineLibrary.casino_lines(4)
	var hits: Array = r.evaluate_paylines_profile(reels, attacks, 4, casino, true, 3)
	_check(hits != null, "left-align profile returns an Array")
	_check(r.last_grid.size() == 4, "last_grid rebuilt to 4 cols (got %d)" % r.last_grid.size())
	for h in hits:
		_check(h.length >= 3, "every left-align hit has length>=3 (got %d)" % h.length)

	# whole-line path runs against the default lines without error.
	var deflines: Array = PaylineLibrary.lines_for(4)
	var hits2: Array = r.evaluate_paylines_profile(reels, attacks, 4, deflines, false, 3)
	_check(hits2 != null, "whole-line profile returns an Array")

	print(("PAYLINE PROFILE TEST PASSED" if _failures == 0 else "PAYLINE PROFILE TEST FAILED: %d" % _failures))
	quit(_failures)
