extends SceneTree

# Headless test: Warden "Regrowth" (L7, Task 30) — stage_regrowth spends Mana and flags the
# pending ally-Regen grant. The ally-picking (_lowest_hp_pct_ally) and attach_effect(&"regen")
# application are orchestrator-level (combat.gd) — they need a real _turn_manager.combatants list
# and a live CombatantPanel to refresh, so they're scene-verified, not unit-tested here. Same
# precedent as Foresight (Task 27).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_regrowth.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- stage_regrowth spends Mana + flags pending when affordable ---
	var warden: Combatant = Combatant.new()
	warden.resource_pool = ResourcePool.new()
	warden.resource_pool.mana = 4
	warden.resource_pool.max_mana = 12
	_check(warden.stage_regrowth(4), "stage succeeds with 4 mana")
	_check(warden.regrowth_pending, "pending flag set")
	_check(warden.resource_pool.mana == 0, "4 mana spent (got %d)" % warden.resource_pool.mana)

	# --- unaffordable → false, no change ---
	_check(not warden.stage_regrowth(4), "stage fails when unaffordable")
	_check(warden.resource_pool.mana == 0, "mana unchanged on failed stage (got %d)" % warden.resource_pool.mana)
	_check(warden.regrowth_pending, "pending flag unchanged (still true) on failed stage")

	# --- a fresh combatant that never staged never has the flag set ---
	var other: Combatant = Combatant.new()
	other.resource_pool = ResourcePool.new()
	other.resource_pool.mana = 0
	other.resource_pool.max_mana = 12
	_check(not other.stage_regrowth(4), "stage fails with 0 mana")
	_check(not other.regrowth_pending, "pending flag stays false when unaffordable from the start")

	print(("REGROWTH TEST PASSED" if _failures == 0 else "REGROWTH TEST FAILED: %d" % _failures))
	quit(_failures)
