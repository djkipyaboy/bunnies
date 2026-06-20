extends SceneTree

# Headless test: Might adds flat damage per damaging hit (round-up order preserved).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_might_damage.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _one_face(tier: ReelFace.ResultTier, mult: float) -> ActionReel:
	var r: ActionReel = ActionReel.new()
	var f: ReelFace = ReelFace.new(); f.result_tier = tier; f.multiplier = mult
	r.faces.append(f)
	return r

func _initialize() -> void:
	var resolver: CombatResolver = CombatResolver.new()
	var SU := ReelFace.ResultTier.SUCCESS
	var NE := ReelFace.ResultTier.NEUTRAL

	# Success, base 10, no type (x1.0), Might +3 -> 13.
	var a: Array = resolver.resolve_combat_phase([_one_face(SU, 1.0)], 10.0, null, [], 1, 3)
	_check(a[0].final_damage == 13, "10x1 + Might 3 = 13 (got %d)" % a[0].final_damage)

	# Default flat_damage_bonus 0 -> unchanged (regression).
	var b: Array = resolver.resolve_combat_phase([_one_face(SU, 1.0)], 10.0)
	_check(b[0].final_damage == 10, "Might default 0 -> 10 (got %d)" % b[0].final_damage)

	# Non-damaging tier (neutral) gets NO flat bonus.
	var c: Array = resolver.resolve_combat_phase([_one_face(NE, 0.0)], 10.0, null, [], 1, 3)
	_check(c[0].final_damage == 0, "neutral + Might 3 -> 0 damage (got %d)" % c[0].final_damage)

	print(("MIGHT DAMAGE TEST PASSED" if _failures == 0 else "MIGHT DAMAGE TEST FAILED: %d" % _failures))
	quit(_failures)
