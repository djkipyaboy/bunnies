extends SceneTree

# Headless test: Ranger "Aimed Shot" (L5, spec Task 23) — stage_aimed_shot spends Stamina and flags
# the pending self-buff. The Mark-dependent magnitude branch (1.6 if the defender is already Marked,
# else 1.3) lives in the orchestrator (combat.gd, alongside the Hunter's Mark attach block) because it
# needs a real _defender reference owned by the combat scene — same precedent as Hunter's Mark's own
# defender-attach logic, which is likewise orchestrator-level and not unit-tested here.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_aimed_shot.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- stage_aimed_shot spends Stamina + flags pending when affordable ---
	var ranger: Combatant = Combatant.new()
	ranger.resource_pool = ResourcePool.new()
	ranger.resource_pool.stamina = 3
	ranger.resource_pool.max_stamina = 10
	_check(ranger.stage_aimed_shot(3), "stage succeeds with 3 stamina")
	_check(ranger.aimed_shot_pending, "pending flag set")
	_check(ranger.resource_pool.stamina == 0, "3 stamina spent (got %d)" % ranger.resource_pool.stamina)

	# --- unaffordable → false, no change ---
	_check(not ranger.stage_aimed_shot(3), "stage fails when unaffordable")
	_check(ranger.resource_pool.stamina == 0, "stamina unchanged on failed stage (got %d)" % ranger.resource_pool.stamina)
	_check(ranger.aimed_shot_pending, "pending flag unchanged (still true) on failed stage")

	# --- a fresh combatant that never staged never has the flag set ---
	var other: Combatant = Combatant.new()
	other.resource_pool = ResourcePool.new()
	other.resource_pool.stamina = 0
	other.resource_pool.max_stamina = 10
	_check(not other.stage_aimed_shot(3), "stage fails with 0 stamina")
	_check(not other.aimed_shot_pending, "pending flag stays false when unaffordable from the start")

	print(("AIMED SHOT TEST PASSED" if _failures == 0 else "AIMED SHOT TEST FAILED: %d" % _failures))
	quit(_failures)
