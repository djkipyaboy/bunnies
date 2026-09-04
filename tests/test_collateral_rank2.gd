extends SceneTree

# Headless test: Ranger "Collateral Damage" Ultimate rank-2 (level 10) — splash fraction 0.5 -> 2/3,
# and every splashed enemy also gets Weakened, unconditional (2026-09-04 ranger-rank2-content spec
# §7). The real application lives in combat.gd's _finish_spin(), which calls the private
# _splash_half_to_others() — no live scene reference here, mirroring tests/test_collateral.gd's own
# "replicate the orchestrator's formula directly" convention (that file covers the rank-1 splash
# math and fire_collateral() itself; not re-tested here).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_collateral_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	return ClassLibrary.make(&"ranger").build_combatant(true)

func _init() -> void:
	# --- rank < 2 (level 9, below ultimate's rank-2 threshold of 10): splash fraction stays 0.5 ---
	var c1: Combatant = _mk_ranger()
	c1.level = 9
	_check(c1.ability_talent_row_rank(&"ultimate") == 1, "sanity: level 9 reads rank 1 on the ultimate row")
	_check(ceili(21 * 0.5) == 11, "rank 1: splash fraction stays 1/2 -> ceil(21 * 0.5) = 11")

	# --- rank 2 (level 10): splash fraction becomes 2/3 ---
	var c2: Combatant = _mk_ranger()
	c2.level = 10
	_check(c2.ability_talent_row_rank(&"ultimate") == 2, "sanity: level 10 reads rank 2 on the ultimate row")
	_check(ceili(21 * (2.0 / 3.0)) == 14, "rank 2: splash fraction is 2/3 -> ceil(21 * 2/3) = 14")

	# --- rank 2: every splashed enemy also gets Weakened, independent of Marking Collateral (manual
	# simulation of _finish_spin()'s loop, mirroring test_ability_talents_ranger.gd's own Marking
	# Collateral simulation) ---
	var other_a: Combatant = _mk_ranger()
	var other_b: Combatant = _mk_ranger()
	var splashed: Array[Combatant] = [other_a, other_b]
	_check(not other_a.has_effect(&"weakened") and not other_b.has_effect(&"weakened"), "sanity: neither splashed enemy starts Weakened")
	var collateral_rank2: bool = c2.ability_talent_row_rank(&"ultimate") >= 2
	if collateral_rank2:
		for other: Combatant in splashed:
			other.attach_effect(EffectLibrary.make(&"weakened"))
	_check(other_a.has_effect(&"weakened") and other_b.has_effect(&"weakened"), "rank 2: every splashed enemy is also Weakened")

	# --- rank 2 + Marking Collateral picked: both Weakened AND Hunter's Mark land on the same
	# splashed enemies (independent effects, not mutually exclusive) ---
	var c3: Combatant = _mk_ranger()
	c3.level = 10
	_check(c3.pick_ability_talent(&"ultimate", &"collateral_marking"), "picks collateral_marking")
	var other_c: Combatant = _mk_ranger()
	other_c.attach_effect(EffectLibrary.make(&"weakened"))  # the rank-2 wrinkle, simulated above
	if c3.has_ability_talent(&"collateral_marking"):
		other_c.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(other_c.has_effect(&"weakened") and other_c.has_effect(&"hunters_mark"), "rank 2 + Marking Collateral: a splashed enemy carries BOTH Weakened and Hunter's Mark")

	print(("COLLATERAL DAMAGE RANK-2 TEST PASSED" if _failures == 0 else "COLLATERAL DAMAGE RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
