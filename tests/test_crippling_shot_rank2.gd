extends SceneTree

# Headless test: Ranger "Crippling Shot" rank-2 (level 8+) — a standalone "Wounded" heal-reduction
# debuff attached alongside Weakened (2026-09-04 ranger-rank2-content spec §5.1). The actual
# rider-attach application lives in combat.gd's _apply_attack() generic rider-attach loop —
# orchestrator-level (needs a running Combat scene's live per-hit attack resolution), NOT headlessly
# tested here, consistent with this codebase's own established convention for Crippling Shot's other
# rider logic (see tests/test_ability_talents_ranger.gd's own header comment). This test proves the
# Wounded effect's own shape (EffectLibrary.make) and the rank gate/duration-matching precondition
# by manually replicating _apply_attack()'s exact conditional, mirroring
# tests/test_collateral.gd's own "replicate the orchestrator's formula directly" convention.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_crippling_shot_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	return ClassLibrary.make(&"ranger").build_combatant(true)

## Manually replicates combat.gd's _apply_attack() generic rider-attach loop's rank-2 conditional
## exactly (spec §5.1): a fresh Wounded effect, duration matching [param weakened_duration] (the
## duration Weakened's own rider got this cast, after apply_rider_talent_adjustments), attached only
## when Crippling Shot's rider (&"weakened") lands on a rank-2 Ranger's hit.
func _apply_rank2_wounded(ranger: Combatant, target: Combatant, weakened_duration: int) -> void:
	if ranger.ability_talent_row_rank(&"ability_l4") >= 2:
		var wounded: Effect = EffectLibrary.make(&"wounded")
		wounded.duration = weakened_duration
		target.attach_effect(wounded)

func _init() -> void:
	# --- the Wounded effect's own shape ---
	var e: Effect = EffectLibrary.make(&"wounded")
	_check(e != null, "EffectLibrary makes wounded")
	_check(e.id == &"wounded", "id is wounded")
	_check(e.kind == Effect.Kind.MULTIPLIER_EDIT, "kind is MULTIPLIER_EDIT (neutral 1.0, the real payload is heal_multiplier)")
	_check(is_equal_approx(e.magnitude, 1.0), "magnitude is neutral (1.0) — does not itself change incoming damage math")
	_check(e.affects_incoming, "affects_incoming is true (matches Hunter's Mark-style 'kind chosen loosely' precedent)")
	_check(is_equal_approx(e.heal_multiplier, 0.5), "heal_multiplier is 0.5 (the real payload, read directly by Combatant.heal())")
	_check(not e.beneficial, "is a debuff")

	# --- rank < 2 (level 7, below ability_l4's rank-2 threshold of 8): Wounded is NOT attached ---
	var c1: Combatant = _mk_ranger()
	c1.level = 7
	var target1: Combatant = _mk_ranger()
	target1.attach_effect(EffectLibrary.make(&"weakened"))
	_apply_rank2_wounded(c1, target1, target1._find_effect(&"weakened").duration)
	_check(not target1.has_effect(&"wounded"), "level 7 (rank 1): target only carries weakened, no wounded")
	_check(target1.has_effect(&"weakened"), "sanity: weakened is still attached")

	# --- rank 2 (level 8+), baseline 2-turn Weakened: Wounded attaches with a MATCHING 2-turn duration ---
	var c2: Combatant = _mk_ranger()
	c2.level = 8
	var target2: Combatant = _mk_ranger()
	target2.attach_effect(EffectLibrary.make(&"weakened"))
	var weakened2: Effect = target2._find_effect(&"weakened")
	_check(weakened2.duration == 2, "sanity: baseline Weakened duration is 2")
	_apply_rank2_wounded(c2, target2, weakened2.duration)
	_check(target2.has_effect(&"weakened") and target2.has_effect(&"wounded"), "level 8 (rank 2): target carries BOTH weakened and wounded")
	_check(target2._find_effect(&"wounded").duration == 2, "level 8: wounded duration matches the baseline 2-turn Weakened (got %d)" % target2._find_effect(&"wounded").duration)

	# --- rank 2, Lasting Crippling picked -> Weakened's own duration is 3, Wounded matches that ---
	var c3: Combatant = _mk_ranger()
	c3.level = 8
	_check(c3.pick_ability_talent(&"ability_l4", &"crippling_lasting"), "picks crippling_lasting")
	var target3: Combatant = _mk_ranger()
	var weakened3: Effect = EffectLibrary.make(&"weakened")
	c3.apply_rider_talent_adjustments(&"weakened", weakened3, target3)
	target3.attach_effect(weakened3)
	_check(target3._find_effect(&"weakened").duration == 3, "sanity: crippling_lasting bumps Weakened's own duration to 3")
	_apply_rank2_wounded(c3, target3, target3._find_effect(&"weakened").duration)
	_check(target3._find_effect(&"wounded").duration == 3, "level 8 + Lasting Crippling: wounded duration matches the extended 3-turn Weakened (got %d)" % target3._find_effect(&"wounded").duration)

	print(("CRIPPLING SHOT RANK-2 TEST PASSED" if _failures == 0 else "CRIPPLING SHOT RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
