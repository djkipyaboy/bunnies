extends SceneTree

# Headless: pure reroll-selection + gamble-transform helpers. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_reroll_selection.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(tier: ReelFace.ResultTier) -> CombatResolver.AttackResult:
	var a: CombatResolver.AttackResult = CombatResolver.AttackResult.new()
	var f: ReelFace = ReelFace.new(); f.result_tier = tier
	a.face = f
	return a

func _initialize() -> void:
	var CF := ReelFace.ResultTier.CRIT_FAILURE
	var F := ReelFace.ResultTier.FAILURE
	var N := ReelFace.ResultTier.NEUTRAL
	var S := ReelFace.ResultTier.SUCCESS
	var CS := ReelFace.ResultTier.CRIT_SUCCESS

	# Priority: crit-fail beats fail beats neutral.
	_check(Combatant.worst_reroll_index([_mk(S), _mk(N), _mk(F), _mk(CF)]) == 3, "picks crit-fail over fail/neutral")
	_check(Combatant.worst_reroll_index([_mk(S), _mk(F), _mk(N)]) == 1, "picks fail over neutral")
	_check(Combatant.worst_reroll_index([_mk(S), _mk(CS), _mk(N)]) == 2, "picks neutral when only neutral qualifies")
	# Tie -> first occurrence.
	_check(Combatant.worst_reroll_index([_mk(CF), _mk(S), _mk(CF)]) == 0, "tie picks FIRST crit-fail")
	# None qualifies (all hits) -> -1.
	_check(Combatant.worst_reroll_index([_mk(S), _mk(CS), _mk(S)]) == -1, "no qualifying reel -> -1")

	# Gamble transform.
	_check(Combatant.gamble_final_damage(CS, 10) == 20, "reroll crit doubles (got %d)" % Combatant.gamble_final_damage(CS, 10))
	_check(Combatant.gamble_final_damage(F, 10) == 0, "reroll fail -> 0")
	_check(Combatant.gamble_final_damage(CF, 10) == 0, "reroll crit-fail -> 0")
	_check(Combatant.gamble_final_damage(S, 10) == 10, "reroll success -> original stands")
	_check(Combatant.gamble_final_damage(N, 10) == 10, "reroll neutral -> original stands")

	print(("REROLL SELECTION TEST PASSED" if _failures == 0 else "REROLL SELECTION TEST FAILED: %d" % _failures))
	quit(_failures)
