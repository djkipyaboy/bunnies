extends SceneTree

# Headless test: ActionReel.make_ability_attack() through the REAL CombatResolver pipeline
# (final review finding #4, 2026-08-13 accuracy-stat spec). test_ability_attack_reel.gd already
# hand-inspects the face composition (50 faces, 5/10/0/30/5 split, riders on hit faces); this test
# proves the composition actually resolves correctly through resolve_combat_phase() — real damage
# dealt and the rider reported on the AttackResult — for both a SUCCESS and a CRIT_SUCCESS landed
# face. Mirrors test_rend_reel.gd's pattern of forcing a deterministic landed face via a single-face
# reel (spin() picks a random index, so a full 50-face ability reel can't be forced to land a
# specific tier without reducing it to one face first).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ability_attack_resolve.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

# Forces a deterministic landed face: builds a full make_ability_attack() reel, picks the first
# face of the requested tier out of it (so the face itself, multiplier, and rider all come from
# the real composition, not hand-authored), then returns a 1-face reel wrapping just that face —
# same technique test_rend_reel.gd's _one_reel() uses to force a single-face spin.
func _forced_ability_reel(type: DamageType, rider: StringName, tier: ReelFace.ResultTier) -> ActionReel:
	var full: ActionReel = ActionReel.make_ability_attack(type, rider)
	var chosen: ReelFace = null
	for f: ReelFace in full.faces:
		if f.result_tier == tier:
			chosen = f
			break
	var r: ActionReel = ActionReel.new()
	r.damage_type = type
	r.is_weapon_attack = full.is_weapon_attack
	r.faces.append(chosen)
	return r

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var resolver: CombatResolver = CombatResolver.new()
	var SU := ReelFace.ResultTier.SUCCESS
	var CS := ReelFace.ResultTier.CRIT_SUCCESS

	# --- SUCCESS-tier face from a real make_ability_attack() reel, resolved end to end ---
	var success_reel: ActionReel = _forced_ability_reel(slashing, &"sundered", SU)
	_check(success_reel.faces[0] != null, "forced a real SUCCESS face out of make_ability_attack's composition")
	var a: Array[CombatResolver.AttackResult] = resolver.resolve_combat_phase([success_reel], 10.0, slashing, [], 1, 0)
	_check(a.size() == 1, "one reel -> one AttackResult")
	_check(a[0].final_damage > 0, "ABILITY_COMPOSITION success face deals real damage through the resolver (got %d)" % a[0].final_damage)
	_check(a[0].rider_effect_id == &"sundered", "resolver reports the ability reel's rider on a SUCCESS hit (got %s)" % a[0].rider_effect_id)

	# --- CRIT_SUCCESS-tier face: still real damage, still carries the rider ---
	var crit_reel: ActionReel = _forced_ability_reel(slashing, &"sundered", CS)
	_check(crit_reel.faces[0] != null, "forced a real CRIT_SUCCESS face out of make_ability_attack's composition")
	var b: Array[CombatResolver.AttackResult] = resolver.resolve_combat_phase([crit_reel], 10.0, slashing, [], 1, 0)
	_check(b[0].final_damage > 0, "ABILITY_COMPOSITION crit-success face deals real damage through the resolver (got %d)" % b[0].final_damage)
	_check(b[0].final_damage > a[0].final_damage, "crit-success deals more damage than a plain success (got %d vs %d)" % [b[0].final_damage, a[0].final_damage])
	_check(b[0].rider_effect_id == &"sundered", "resolver reports the ability reel's rider on a CRIT_SUCCESS hit (got %s)" % b[0].rider_effect_id)

	print(("ABILITY ATTACK RESOLVE TEST PASSED" if _failures == 0 else "ABILITY ATTACK RESOLVE TEST FAILED: %d" % _failures))
	quit(_failures)
