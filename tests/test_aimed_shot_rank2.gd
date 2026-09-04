extends SceneTree

# Headless test: Ranger "Aimed Shot" rank-2 (level 6+) stacking mechanic (2026-09-04
# ranger-rank2-content spec §3.1) — recasting while Empowered is still active stacks the bonus
# magnitude (+0.10/stack, capped at 2 additional stacks = 3 total applications) instead of
# refreshing it. Verified via a real Combat instance's _commit_main1(), mirroring
# tests/test_grand_sacrifice.gd's manual-wiring technique. Aimed Shot's own rank-1 baseline
# (stage_aimed_shot spends Stamina + flags pending) is already covered by
# tests/test_aimed_shot.gd and is NOT re-tested here.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_aimed_shot_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _build_combat(ranger: Combatant, target: Combatant) -> Combat:
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst._turn_manager.combatants = [ranger, target]
	inst._panels[ranger] = CombatantPanel.new()
	inst._panels[target] = CombatantPanel.new()
	inst._attacker = ranger
	inst._defender = target
	return inst

func _free_combat(inst: Combat) -> void:
	inst.queue_free()
	await process_frame

## Directly stages Aimed Shot on [param ranger] (bypassing MainPhasePlan's cooldown/reel-cap
## gating, exactly like tests/test_aimed_shot.gd's own precedent) and commits it on [param inst],
## returning the resulting Empowered effect.
func _cast_aimed_shot(inst: Combat, ranger: Combatant) -> Effect:
	ranger.aimed_shot_pending = true
	inst._plan = MainPhasePlan.new(ranger, 0, 5, 2, null)
	inst._commit_main1()
	return ranger._find_effect(&"empowered")

## Case 1: rank < 2 (level 5, below ability_l2's rank-2 threshold of 6) — recasting while Empowered
## is still active just REFRESHES to the same base magnitude, never stacks.
func _run_rank1_regression() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 5
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)  # unmarked -> base 1.3
	var inst: Combat = await _build_combat(ranger, target)

	var e1: Effect = _cast_aimed_shot(inst, ranger)
	_check(e1 != null and is_equal_approx(e1.magnitude, 1.3), "level 5 cast 1: base magnitude 1.3 (got %s)" % [e1.magnitude if e1 != null else "null"])
	var e2: Effect = _cast_aimed_shot(inst, ranger)
	_check(e2 != null and is_equal_approx(e2.magnitude, 1.3), "level 5 (rank 1) recast while still Empowered: still 1.3, no stacking (got %s)" % [e2.magnitude if e2 != null else "null"])
	_check(ranger.aimed_shot_stacks == 0, "rank 1: aimed_shot_stacks never increments (got %d)" % ranger.aimed_shot_stacks)

	await _free_combat(inst)

## Case 2: rank 2 (level 6+), target UNMARKED -> base 1.3, stacks 1.3 -> 1.4 -> 1.5 -> capped 1.5.
func _run_rank2_stacking_unmarked() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 6
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	var expected: Array[float] = [1.3, 1.4, 1.5, 1.5]
	for i: int in range(4):
		var e: Effect = _cast_aimed_shot(inst, ranger)
		_check(e != null and is_equal_approx(e.magnitude, expected[i]), "level 6 unmarked cast %d: magnitude %.1f (got %s)" % [i + 1, expected[i], e.magnitude if e != null else "null"])

	await _free_combat(inst)

## Case 3: rank 2, target MARKED -> base 1.6, stacks 1.6 -> 1.7 -> 1.8 -> capped 1.8.
func _run_rank2_stacking_marked() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 6
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	target.attach_effect(EffectLibrary.make(&"hunters_mark"))
	var inst: Combat = await _build_combat(ranger, target)

	var expected: Array[float] = [1.6, 1.7, 1.8, 1.8]
	for i: int in range(4):
		var e: Effect = _cast_aimed_shot(inst, ranger)
		_check(e != null and is_equal_approx(e.magnitude, expected[i]), "level 6 marked cast %d: magnitude %.1f (got %s)" % [i + 1, expected[i], e.magnitude if e != null else "null"])

	await _free_combat(inst)

## Case 4: a fresh cast AFTER Empowered has expired resets to the base magnitude, not continuing
## the old stack count (remove_effect() simulates natural expiry without waiting out real turns).
func _run_reset_after_expiry() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 6
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	_cast_aimed_shot(inst, ranger)
	_cast_aimed_shot(inst, ranger)
	_check(ranger.aimed_shot_stacks == 1, "sanity: 2 casts in a row leave 1 stack")
	ranger.remove_effect(&"empowered")  # simulate the buff naturally expiring
	var e: Effect = _cast_aimed_shot(inst, ranger)
	_check(e != null and is_equal_approx(e.magnitude, 1.3), "fresh cast after expiry resets to the base magnitude (got %s)" % [e.magnitude if e != null else "null"])
	_check(ranger.aimed_shot_stacks == 0, "fresh cast after expiry resets aimed_shot_stacks to 0 (got %d)" % ranger.aimed_shot_stacks)

	await _free_combat(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_stacking_unmarked()
	await _run_rank2_stacking_marked()
	await _run_reset_after_expiry()
	print(("AIMED SHOT RANK-2 TEST PASSED" if _failures == 0 else "AIMED SHOT RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
