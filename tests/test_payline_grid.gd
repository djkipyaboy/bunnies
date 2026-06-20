extends SceneTree

# Headless test: CombatResolver builds the 3xW weapon grid, reports landed_index, emits
# paylines_resolved, and rounds damage UP. Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_payline_grid.gd

var _failures: int = 0
var _payline_hits: Array = []
var _payline_signal_count: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else:
		_failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _on_paylines_resolved(hits: Array) -> void:
	_payline_signal_count += 1
	_payline_hits = hits

# A reel whose every face is the same tier -> any landed window is uniform (deterministic grid).
func _uniform_reel(tier: ReelFace.ResultTier, type: DamageType = null) -> ActionReel:
	var r: ActionReel = ActionReel.new()
	r.damage_type = type
	for i: int in range(10):
		var f: ReelFace = ReelFace.new()
		f.result_tier = tier
		f.multiplier = 1.0 if tier == ReelFace.ResultTier.SUCCESS else 0.0
		r.faces.append(f)
	return r

func _initialize() -> void:
	var SU := ReelFace.ResultTier.SUCCESS
	var resolver: CombatResolver = CombatResolver.new()
	resolver.paylines_resolved.connect(_on_paylines_resolved)

	# 3 weapon reels (all-success) + 1 spliced reel -> grid must be width 3 (splice excluded).
	var reels: Array[ActionReel] = [_uniform_reel(SU), _uniform_reel(SU), _uniform_reel(SU), _uniform_reel(SU)]
	var attacks: Array = resolver.resolve_combat_phase(reels, 10.0, null, [], 3)
	_check(resolver.last_grid.size() == 3, "grid width == weapon_reel_count 3, splice excluded (got %d)" % resolver.last_grid.size())
	_check(resolver.last_grid[0].size() == 3, "grid has 3 rows (got %d)" % resolver.last_grid[0].size())
	_check(_payline_signal_count == 1, "paylines_resolved emitted once (got %d)" % _payline_signal_count)
	_check(_payline_hits.size() == 8, "all-success 3x3 weapon grid -> 8 line hits (got %d)" % _payline_hits.size())

	# landed_index reported and consistent with the landed face's tier.
	_check(attacks[0].landed_index >= 0 and attacks[0].landed_index < 10, "landed_index in range (got %d)" % attacks[0].landed_index)
	_check(reels[0].faces[attacks[0].landed_index].result_tier == attacks[0].face.result_tier, "landed_index points at the landed face's tier")

	# Round UP: base 8, success x1.0, type x0.75 -> 6.0 (exact); use a fractional case to prove ceil.
	# base 10 x success(1.0) x 1.0(no type) = 10 (exact). Prove ceil via the line bonus in Task 4.
	# Here assert per-reel damage uses ceil on a fractional product:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	# crushing vs earth uses default_multiplier (1.0) -> 10*1.0*1.0 = 10. Pick a reel/type giving x.5+:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")  # slashing vs earth = 1.25
	var dmg_reels: Array[ActionReel] = [_uniform_reel(SU, slashing)]
	var dmg_attacks: Array = resolver.resolve_combat_phase(dmg_reels, 10.0, earth, [], 1)
	_check(dmg_attacks[0].final_damage == 13, "10 x1.0 x1.25 = 12.5 -> ceil 13 (got %d)" % dmg_attacks[0].final_damage)

	print(("PAYLINE GRID TEST PASSED" if _failures == 0 else "PAYLINE GRID TEST FAILED: %d" % _failures))
	quit(_failures)
