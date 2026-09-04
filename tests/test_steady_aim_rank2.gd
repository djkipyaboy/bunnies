extends SceneTree

# Headless test: Ranger "Steady Aim" amplified (level 9+) passive (2026-09-04 ranger-rank2-content
# spec §6) — the +10%-vs-Marked baseline bumps to +20%, and (with Deadeye picked) Marksman's Call's
# independently-resolved reel gains Deadeye's own +15%-on-crit-vs-Marked bonus, which it previously
# never received (a gap the talent-tree rework's final review flagged). The Deadeye/Marksman's Call
# bridge itself lives in combat.gd's _fire_marksmans_call() — orchestrator-level (needs a running
# Combat scene's _resolver), NOT headlessly tested here, consistent with this codebase's own
# established convention for Marksman's Call's other math (see
# tests/test_ability_talents_ranger.gd's own header comment: "Marksman's Call's own resolver math is
# covered in tests/test_marksmans_call.gd"). This test proves the rank gate itself.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_steady_aim_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_ranger() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	c.passive_ability_id = &"steady_aim"
	return c

func _init() -> void:
	# --- rank < 2 (level 8, below passive's amplified threshold of 9): stays +10% ---
	var c1: Combatant = _mk_ranger()
	c1.level = 8
	var marked1: Combatant = _mk_ranger()
	marked1.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c1.passive_outgoing_multiplier(marked1), 1.10), "level 8 (rank 1): Steady Aim stays +10%% vs a Marked defender (got %.3f)" % c1.passive_outgoing_multiplier(marked1))

	# --- amplified (level 9+): +20% ---
	var c2: Combatant = _mk_ranger()
	c2.level = 9
	var marked2: Combatant = _mk_ranger()
	marked2.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(is_equal_approx(c2.passive_outgoing_multiplier(marked2), 1.20), "level 9 (amplified): Steady Aim is +20%% vs a Marked defender (got %.3f)" % c2.passive_outgoing_multiplier(marked2))

	# --- the trigger-widening talents (Controlled Aim / Wider Aim) are unaffected by amplification —
	# they still only decide WHETHER the bonus fires, now at the bigger +20% magnitude. ---
	var c3: Combatant = _mk_ranger()
	c3.level = 9
	_check(c3.pick_ability_talent(&"passive", &"steady_wider"), "picks steady_wider")
	var weakened3: Combatant = _mk_ranger()
	weakened3.attach_effect(EffectLibrary.make(&"weakened"))
	_check(is_equal_approx(c3.passive_outgoing_multiplier(weakened3), 1.20), "level 9 + steady_wider vs a merely-Weakened defender: +20%% (got %.3f)" % c3.passive_outgoing_multiplier(weakened3))

	# --- amplified-rank + Deadeye bridge precondition (spec §6.2): the exact gate combat.gd's
	# _fire_marksmans_call() reads — full application deferred to playtest. ---
	var c4: Combatant = _mk_ranger()
	c4.level = 9
	_check(c4.pick_ability_talent(&"passive", &"steady_deadeye"), "picks steady_deadeye")
	_check(c4.ability_talent_row_rank(&"passive") >= 2 and c4.has_ability_talent(&"steady_deadeye"), "sanity: the Marksman's Call/Deadeye bridge's own gate reads true at level 9 with Deadeye picked")
	var c5: Combatant = _mk_ranger()
	c5.level = 8
	_check(not (c5.ability_talent_row_rank(&"passive") >= 2 and c5.has_ability_talent(&"steady_deadeye")), "sanity: the bridge's gate reads false below level 9 (passive row unlocks at L9)")

	print(("STEADY AIM RANK-2 TEST PASSED" if _failures == 0 else "STEADY AIM RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
