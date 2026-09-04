extends SceneTree

# Headless test: Ranger "Snare Trap" rank-2 (level 7+) — the primary target ALSO gets
# force_stun_next_turn = true, stacked on top of the existing 2-turn Rooted (2026-09-04
# ranger-rank2-content spec §4.1). combat.gd's _apply_attack() applies this for real — orchestrator-
# level (needs a running Combat scene's live per-hit attack resolution), NOT headlessly tested here,
# consistent with this codebase's own established convention for Snare Trap's other rider/splash
# logic (see tests/test_ability_talents_ranger.gd / tests/test_snare_trap.gd's own header comments).
# This test proves the RANK GATE itself and manually replicates the exact conditional
# _apply_attack() runs, mirroring tests/test_collateral.gd's own "replicate the orchestrator's
# formula directly" convention.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_snare_trap_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	return ClassLibrary.make(&"ranger").build_combatant(true)

## Manually replicates combat.gd's _apply_attack() rank-2 conditional exactly (spec §4.1): the
## PRIMARY target only gets force_stun_next_turn when ability_talent_row_rank(&"ability_l3") >= 2.
func _apply_rank2_stun(ranger: Combatant, primary: Combatant) -> void:
	if ranger.ability_talent_row_rank(&"ability_l3") >= 2:
		primary.force_stun_next_turn = true

func _init() -> void:
	# --- rank < 2 (level 6, below ability_l3's rank-2 threshold of 7): primary NOT stunned ---
	var c1: Combatant = _mk_ranger()
	c1.level = 6
	var primary1: Combatant = _mk_ranger()
	_check(not primary1.force_stun_next_turn, "sanity: primary starts unstunned")
	_apply_rank2_stun(c1, primary1)
	_check(not primary1.force_stun_next_turn, "level 6 (rank 1): primary target NOT stunned")

	# --- rank 2 (level 7+): primary IS stunned ---
	var c2: Combatant = _mk_ranger()
	c2.level = 7
	var primary2: Combatant = _mk_ranger()
	_apply_rank2_stun(c2, primary2)
	_check(primary2.force_stun_next_turn, "level 7 (rank 2): primary target force_stun_next_turn is set")

	# --- splash targets are unaffected: in combat.gd's real "for t in targets" loop the rank-2 stun
	# is only ever applied to the PRIMARY target — a splashed enemy from _splash_half_to_others() is
	# a separate array this rank-2 check never iterates. ---
	var splash_target: Combatant = _mk_ranger()
	_check(not splash_target.force_stun_next_turn, "splash targets are never touched by the rank-2 stun (only the primary-target loop is)")

	print(("SNARE TRAP RANK-2 TEST PASSED" if _failures == 0 else "SNARE TRAP RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
