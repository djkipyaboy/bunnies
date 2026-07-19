extends SceneTree

## Headless regression test for finding 2 of the 2026-07-19 final whole-branch review
## (The Hollow Warden boss fight): combat.gd's Darkness Rampage weapon.base_damage
## restore is normally done in _finish_spin() (keyed on base_damage == 18.0), which never
## runs if the boss's turn is interrupted before reaching a spin — e.g. the boss is STUNNED
## the same turn _on_turn_started() set up a Darkness Rampage turn. That leaves
## weapon.base_damage stuck at 18.0 and darkness_rampage_spins_remaining stuck at 1, which
## can leak into the boss's NEXT real attack if phase two then ends before that turn resolves.
##
## The fix adds a symmetric defensive reset in combat.gd's new _sync_boss_darkness_rampage_state()
## (called from _on_turn_started() for every boss turn): when boss_phase_two_active is FALSE,
## it explicitly resets weapon.base_damage to 12.0 and darkness_rampage_spins_remaining to 0 —
## covering both "never entered phase 2" and "phase 2 ended before this turn." This test drives
## that reset directly (without needing to simulate the full stunned-turn/_on_turn_started
## side-effect chain) by:
##   1. Simulating what _on_turn_started() would have set on an INTERRUPTED phase-two turn
##      (boss_phase_two_active = true, weapon.base_damage = 18.0, darkness_rampage_spins_remaining = 1)
##      — but never calling _finish_spin(), so the normal restore never fires.
##   2. Simulating phase two ending without a restore ever happening (boss_phase_two_active = false).
##   3. Calling _sync_boss_darkness_rampage_state() directly — the same method
##      _on_turn_started() calls for every boss turn — and asserting the stale state is cleaned up.
##
## Uses the _failures/quit(_failures) exit-code pattern (not a bare quit()) — this project's own
## history (test_boss_phase_transition.gd's own commit trail) has repeatedly caught that exact
## bug in this plan already; do not reintroduce it.

var _instance: Node
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	var combat: Node = _instance
	var boss: Combatant = EnemyLibrary.make(&"hollow_warden")

	# Step 1: simulate what _on_turn_started() would have set up on an interrupted phase-two turn.
	boss.boss_phase_two_active = true
	boss.weapon.base_damage = 18.0
	boss.darkness_rampage_spins_remaining = 1
	_check(boss.weapon.base_damage == 18.0, "setup: weapon.base_damage is 18.0 (Darkness Rampage active)")
	_check(boss.darkness_rampage_spins_remaining == 1, "setup: darkness_rampage_spins_remaining is 1")

	# Step 2: simulate phase two ending WITHOUT _finish_spin() ever having run to restore the weapon
	# (the exact scenario this fix targets — a stunned boss turn that never reaches a spin).
	boss.boss_phase_two_active = false
	_check(boss.weapon.base_damage == 18.0, "confirm the stale 18.0 is still in place before the fix runs (no restore has happened yet)")

	# Step 3: the fix — the same method _on_turn_started() calls for every boss turn.
	combat._sync_boss_darkness_rampage_state(boss)

	_check(boss.weapon.base_damage == 12.0, "weapon.base_damage is reset to 12.0 once phase two is no longer active (got %s)" % boss.weapon.base_damage)
	_check(boss.darkness_rampage_spins_remaining == 0, "darkness_rampage_spins_remaining is reset to 0 once phase two is no longer active (got %d)" % boss.darkness_rampage_spins_remaining)

	# Sanity check: the normal phase-two setup path (called via the same method) still works —
	# this fix must not weaken the existing Darkness Rampage turn setup.
	boss.boss_phase_two_active = true
	combat._sync_boss_darkness_rampage_state(boss)
	_check(boss.weapon.base_damage == 18.0, "the normal phase-two setup path still sets weapon.base_damage to 18.0")
	_check(boss.darkness_rampage_spins_remaining == 1, "the normal phase-two setup path still sets darkness_rampage_spins_remaining to 1")
	_check(boss.turn_reels.size() == 4, "the normal phase-two setup path still builds 4 turn reels")

	_instance.free()
	print(("DARKNESS RAMPAGE WEAPON DAMAGE SAFETY TEST PASSED" if _failures == 0 else "DARKNESS RAMPAGE WEAPON DAMAGE SAFETY TEST FAILED: %d" % _failures))
	quit(_failures)
	return true
