extends SceneTree

# Headless: resolver can re-resolve a single reel into a fresh AttackResult, and re-score paylines from
# a swapped attacks array. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_reresolve_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var r: CombatResolver = CombatResolver.new()

	# reresolve_reel returns a fresh, valid AttackResult for the reel.
	var reel: ActionReel = ActionReel.make_default(slashing)
	var a: CombatResolver.AttackResult = r.reresolve_reel(reel, 10.0, null, 0)
	_check(a != null and a.face != null, "reresolve_reel returns a valid AttackResult")
	_check(a.landed_index >= 0 and a.landed_index < reel.faces.size(), "landed_index within strip (got %d)" % a.landed_index)

	# evaluate_paylines builds a grid + returns an Array without emitting (no crash, deterministic shape).
	var reels: Array[ActionReel] = [ActionReel.make_default(slashing), ActionReel.make_default(slashing), ActionReel.make_default(slashing)]
	var attacks: Array[CombatResolver.AttackResult] = []
	for rr: ActionReel in reels:
		attacks.append(r.reresolve_reel(rr, 10.0, null, 0))
	var hits: Array = r.evaluate_paylines(reels, attacks, 3, [])
	_check(hits != null, "evaluate_paylines returns an Array (got %s)" % str(hits))
	_check(r.last_grid.size() == 3, "last_grid rebuilt to 3 columns (got %d)" % r.last_grid.size())

	# defer_paylines suppresses the auto-emit: connect a counter and confirm 0 emissions.
	var emitted: Array[int] = [0]
	r.paylines_resolved.connect(func(_h: Array) -> void: emitted[0] += 1)
	r.resolve_combat_phase(reels, 10.0, null, [], 3, 0, [], true)
	_check(emitted[0] == 0, "defer_paylines=true suppresses emit (got %d)" % emitted[0])
	r.resolve_combat_phase(reels, 10.0, null, [], 3, 0, [], false)
	_check(emitted[0] == 1, "defer_paylines=false emits once (got %d)" % emitted[0])

	# Regression (2026-07-10 review, Finding 1): combat.gd's _apply_post_spin_rerolls feeds
	# reresolve_reel() a flat_damage_bonus of might_damage_bonus_per_reel(reel_count) — the
	# reel-count-NORMALIZED Might bonus the main spin path already uses — NOT raw effective_stats().might.
	# Assert the resolver-level contract directly: reresolve_reel adds whatever flat_damage_bonus it's
	# given, so passing the normalized bonus must produce the normalized total, and the (wrong) raw
	# value must produce a different total than the correct one.
	var attacker: Combatant = Combatant.new()
	var mstats: Stats = Stats.new()
	mstats.might = 8  # power = 8 * MIGHT_TO_POWER_RATIO(2.0) = 16.0
	attacker.base_stats = mstats
	var reel_count: int = 3
	var raw_might: int = attacker.effective_stats().might  # 8
	var normalized_bonus: int = attacker.might_damage_bonus_per_reel(reel_count)  # ceil(16.0 / 3) = 6
	_check(raw_might != normalized_bonus, "sanity: raw Might (%d) and normalized bonus (%d) actually differ" % [raw_might, normalized_bonus])

	# A single-face reel with a guaranteed HIT (SUCCESS, ×1.0) so final_damage is deterministic.
	var hit_face: ReelFace = ReelFace.new()
	hit_face.result_tier = ReelFace.ResultTier.SUCCESS
	hit_face.multiplier = 1.0
	var forced_hit_reel: ActionReel = ActionReel.new()
	forced_hit_reel.faces = [hit_face]
	forced_hit_reel.damage_type = slashing

	var base_dmg: float = 10.0
	var correct: CombatResolver.AttackResult = r.reresolve_reel(forced_hit_reel, base_dmg, null, normalized_bonus)
	var expected_damage: int = ceili(base_dmg * 1.0 * 1.0) + normalized_bonus
	_check(correct.final_damage == expected_damage, "reresolve_reel w/ NORMALIZED bonus gives the expected total (got %d want %d)" % [correct.final_damage, expected_damage])

	var if_raw_were_used: CombatResolver.AttackResult = r.reresolve_reel(forced_hit_reel, base_dmg, null, raw_might)
	_check(if_raw_were_used.final_damage != correct.final_damage, "raw Might (the old bug) would have produced a different, wrong total (%d vs correct %d)" % [if_raw_were_used.final_damage, correct.final_damage])

	print(("RERESOLVE TEST PASSED" if _failures == 0 else "RERESOLVE TEST FAILED: %d" % _failures))
	quit(_failures)
