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

	print(("RERESOLVE TEST PASSED" if _failures == 0 else "RERESOLVE TEST FAILED: %d" % _failures))
	quit(_failures)
