extends SceneTree

## Headless test for the 2026-07-23 playtest feedback: turn order was hard to track, so the phase
## label now also shows the current round (surfaced from TurnManager.round_number, which already
## existed and just was never displayed). Mirrors test_hollow_warden_full_sequence.gd's pattern of
## instantiating combat.tscn directly and driving its handlers, without going through the
## selection-overlay UI.

var _instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Combat = _instance as Combat
		combat._on_round_started(1)
		combat._on_phase_changed(PhaseManager.Phase.UPKEEP)
		_check(combat._phase_label.text == "Round 1 — Phase: UPKEEP", "round 1's phase label reads 'Round 1 — Phase: UPKEEP', got: %s" % combat._phase_label.text)

		combat._on_phase_changed(PhaseManager.Phase.MAIN_1)
		_check(combat._phase_label.text == "Round 1 — Phase: MAIN_1", "phase changes within the same round keep the round number")

		combat._on_round_started(2)
		_check(combat._current_round == 2, "_on_round_started updates _current_round")
		combat._on_phase_changed(PhaseManager.Phase.UPKEEP)
		_check(combat._phase_label.text == "Round 2 — Phase: UPKEEP", "the label ticks up to Round 2 when a new round starts")

		print(("COMBAT ROUND COUNTER TEST PASSED" if _failures == 0 else "COMBAT ROUND COUNTER TEST FAILED: %d" % _failures))
		quit(_failures)
	return false
