extends SceneTree

# Headless test: Ranger "Hunter's Mark" rank-2 (level 5+) duration bump (2026-09-04
# ranger-rank2-content spec §2.1) — verified end-to-end via a real Combat instance's
# _commit_main1(), mirroring tests/test_grand_sacrifice.gd's manual-wiring technique (fires for
# real without driving a full turn/spin). Hunter's Mark's own rank-1 baseline (duration 3), the
# hunters_mark_pending flag, and the crit-fail->hit reel-swap math are already covered by
# tests/test_hunters_mark.gd and are NOT re-tested here. The rank-2 ally-crit Bonus-Meter-charge
# mechanic (spec §2.2) needs live per-hit state across TWO combatants inside _apply_attack() —
# orchestrator-level, precondition-only below (this codebase's established convention for that kind
# of mechanic — see tests/test_ability_talents_ranger.gd's own header comment), full behavior
# deferred to playtest.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_hunters_mark_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Wires a real Combat instance's minimal state so _commit_main1() runs for real (mirrors
## tests/test_grand_sacrifice.gd's _build_combat), without driving a full turn/spin.
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
	inst._plan = MainPhasePlan.new(ranger, 0, 5, 2, null)
	return inst

func _free_combat(inst: Combat) -> void:
	inst.queue_free()
	await process_frame

## Case 1: level 4 (below base_ability's rank-2 threshold of 5) -> duration stays the rank-1 baseline (3).
func _run_rank1_regression() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 4
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	inst._plan.toggle_ability()
	inst._commit_main1()
	var mark: Effect = target._find_effect(&"hunters_mark")
	_check(mark != null and mark.duration == 3, "level 4 (rank 1): Hunter's Mark duration stays 3 (got %s)" % [mark.duration if mark != null else "null"])

	await _free_combat(inst)

## Case 2: level 5+ (base_ability rank 2) -> duration bumps to 4.
func _run_rank2_duration() -> void:
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = 5
	var target: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	var inst: Combat = await _build_combat(ranger, target)

	inst._plan.toggle_ability()
	inst._commit_main1()
	var mark: Effect = target._find_effect(&"hunters_mark")
	_check(mark != null and mark.duration == 4, "level 5 (rank 2): Hunter's Mark duration bumps to 4 (got %s)" % [mark.duration if mark != null else "null"])
	_check(ranger.ability_talent_row_rank(&"base_ability") == 2, "sanity: level 5 reads rank 2 on the base_ability row (the same read _apply_attack() gates the ally-crit meter-charge mechanic on, spec §2.2)")

	await _free_combat(inst)

func _initialize() -> void:
	await _run_rank1_regression()
	await _run_rank2_duration()
	print(("HUNTERS MARK RANK-2 TEST PASSED" if _failures == 0 else "HUNTERS MARK RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
