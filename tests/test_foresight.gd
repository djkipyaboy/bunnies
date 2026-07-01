extends SceneTree

# Headless test: Seer "Foresight" (L7, Task 27) — stage_foresight spends Mana and flags the
# pending ally-shield. The ally-picking (_lowest_hp_pct_ally) and apply_shield() application are
# orchestrator-level (combat.gd) — they need a real _turn_manager.combatants list and a live
# CombatantPanel to refresh, so they're scene-verified, not unit-tested here. Same precedent as
# Hunter's Mark / Aimed Shot (Task 22/23): the pending-flag stage is the headless-testable half.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_foresight.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- stage_foresight spends Mana + flags pending when affordable ---
	var seer: Combatant = Combatant.new()
	seer.resource_pool = ResourcePool.new()
	seer.resource_pool.mana = 4
	seer.resource_pool.max_mana = 15
	_check(seer.stage_foresight(4), "stage succeeds with 4 mana")
	_check(seer.foresight_pending, "pending flag set")
	_check(seer.resource_pool.mana == 0, "4 mana spent (got %d)" % seer.resource_pool.mana)

	# --- unaffordable → false, no change ---
	_check(not seer.stage_foresight(4), "stage fails when unaffordable")
	_check(seer.resource_pool.mana == 0, "mana unchanged on failed stage (got %d)" % seer.resource_pool.mana)
	_check(seer.foresight_pending, "pending flag unchanged (still true) on failed stage")

	# --- a fresh combatant that never staged never has the flag set ---
	var other: Combatant = Combatant.new()
	other.resource_pool = ResourcePool.new()
	other.resource_pool.mana = 0
	other.resource_pool.max_mana = 15
	_check(not other.stage_foresight(4), "stage fails with 0 mana")
	_check(not other.foresight_pending, "pending flag stays false when unaffordable from the start")

	print(("FORESIGHT TEST PASSED" if _failures == 0 else "FORESIGHT TEST FAILED: %d" % _failures))
	quit(_failures)
