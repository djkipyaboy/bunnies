extends SceneTree

## Headless test: the new Combatant fields/methods this plan's boss orchestration needs all default
## correctly and behave as plain data (spec 2026-07-19 §3.3/§3.5) — no orchestrator logic here, just
## confirming the fields/methods exist with the right shapes and defaults before later tasks wire
## real behavior around them.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	_check(c.boss_phase_two_active == false, "boss_phase_two_active defaults false")
	_check(c.boss_turns_taken == 0, "boss_turns_taken defaults 0")
	_check(c.boss_last_phase_trigger_turn == -1, "boss_last_phase_trigger_turn defaults -1")
	_check(c.boss_phase_minion_ids.is_empty(), "boss_phase_minion_ids defaults empty")
	_check(c.boss_reinforcement_ids.is_empty(), "boss_reinforcement_ids defaults empty")
	_check(c.heal_boss_pending == false, "heal_boss_pending defaults false")
	_check(c.curse_party_pending == false, "curse_party_pending defaults false")
	_check(c.darkness_rampage_spins_remaining == 0, "darkness_rampage_spins_remaining defaults 0")
	_check(not c.is_darkness_rampage_active(), "is_darkness_rampage_active() is false by default")
	c.darkness_rampage_spins_remaining = 1
	_check(c.is_darkness_rampage_active(), "is_darkness_rampage_active() is true once spins are set")
	c.consume_darkness_rampage_spin()
	_check(c.darkness_rampage_spins_remaining == 0, "consume_darkness_rampage_spin() decrements to 0")
	_check(not c.is_darkness_rampage_active(), "is_darkness_rampage_active() is false again after consuming")
	c.consume_darkness_rampage_spin()  # already 0 — must not go negative
	_check(c.darkness_rampage_spins_remaining == 0, "consume_darkness_rampage_spin() at 0 stays 0 (no underflow)")

	var other: Combatant = Combatant.new()
	c.boss_phase_minion_ids = [other]
	c.boss_reinforcement_ids = [other, other]
	_check(c.boss_phase_minion_ids.size() == 1, "boss_phase_minion_ids holds Combatant references")
	_check(c.boss_reinforcement_ids.size() == 2, "boss_reinforcement_ids holds Combatant references")

	print(("BOSS COMBATANT FIELDS TEST PASSED" if _failures == 0 else "BOSS COMBATANT FIELDS TEST FAILED: %d" % _failures))
	quit(_failures)
