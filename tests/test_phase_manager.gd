extends SceneTree

# Headless test for PhaseManager — MTG-style phase order (DESIGN.md §4.8).
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_phase_manager.gd

var _failures: int = 0
var _phase_log: Array[int] = []
var _turn_finished_count: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _on_phase_changed(phase: int) -> void:
	_phase_log.append(phase)

func _on_turn_finished() -> void:
	_turn_finished_count += 1

func _initialize() -> void:
	var pm: PhaseManager = PhaseManager.new()
	pm.phase_changed.connect(_on_phase_changed)
	pm.turn_finished.connect(_on_turn_finished)

	# start_turn() runs Upkeep -> Main 1 -> Combat, then PAUSES for the spin.
	pm.start_turn()
	_check(_phase_log == [PhaseManager.Phase.UPKEEP, PhaseManager.Phase.MAIN_1, PhaseManager.Phase.COMBAT],
		"start_turn pauses at Combat: %s" % str(_phase_log))
	_check(pm.current_phase == PhaseManager.Phase.COMBAT, "current_phase is COMBAT while paused")
	_check(_turn_finished_count == 0, "turn not finished before spin resolves")

	# resume_after_combat() finishes Main 2 -> End and ends the turn.
	pm.resume_after_combat()
	_check(_phase_log == [
			PhaseManager.Phase.UPKEEP, PhaseManager.Phase.MAIN_1, PhaseManager.Phase.COMBAT,
			PhaseManager.Phase.MAIN_2, PhaseManager.Phase.END],
		"full phase order Upkeep->Main1->Combat->Main2->End: %s" % str(_phase_log))
	_check(_turn_finished_count == 1, "turn_finished fired once (got %d)" % _turn_finished_count)

	print(("PHASE MANAGER TEST PASSED" if _failures == 0 else "PHASE MANAGER TEST FAILED: %d" % _failures))
	quit(_failures)
