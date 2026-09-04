extends SceneTree

# Headless test: CombatResolver.resolve_single_reel() (2026-09-03 ranger-talent-tree spec §3.2,
# "Marksman's Call") — the one new resolver method this feature needs: a single-reel resolve that,
# unlike reresolve_reel() (which hardcodes damage_multiplier = 1.0 for the Chancer reroll/gamble
# paths, which apply their own separate multiplier afterward), actually applies the given
# damage_multiplier — Marksman's Call needs the Ranger's own full outgoing/incoming multiplier
# product baked in, exactly like a normal weapon-attack reel. The full orchestrator wiring (firing
# once per ally-turn via _finish_spin's hook, _fire_marksmans_call's own damage/log/meter-charge
# application) is orchestrator-level (combat.gd) and requires a running Combat scene — NOT
# headlessly tested here, consistent with this codebase's own documented precedent
# (tests/test_ability_talents_ranger.gd's header comment).
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_marksmans_call.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _make_single_face_reel(type: DamageType, tier: ReelFace.ResultTier, multiplier: float) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	var face: ReelFace = ReelFace.new()
	face.result_tier = tier
	face.multiplier = multiplier
	reel.faces = [face]
	return reel

func _init() -> void:
	var piercing: DamageType = load("res://combat/resources/types/piercing.tres")
	var resolver: CombatResolver = CombatResolver.new()

	# A single guaranteed-SUCCESS-face reel makes the "spin" fully deterministic, isolating the
	# math this test actually cares about (damage_multiplier's application).
	var reel: ActionReel = _make_single_face_reel(piercing, ReelFace.ResultTier.SUCCESS, 1.0)
	var attack: CombatResolver.AttackResult = resolver.resolve_single_reel(reel, 10.0, piercing, 2, 1.5)
	# base 10.0 * multiplier 1.0 * type_mult 1.0 (piercing vs piercing = neutral default) = 10.0,
	# then * damage_multiplier 1.5 = 15.0, ceil'd, + flat_damage_bonus 2 = 17.
	_check(attack.final_damage == 17, "resolve_single_reel applies damage_multiplier (got %d, want 17)" % attack.final_damage)
	_check(attack.face.result_tier == ReelFace.ResultTier.SUCCESS, "sanity: the single face always lands")

	# damage_multiplier == 1.0 (the neutral default) matches reresolve_reel()'s own existing shape.
	var reel2: ActionReel = _make_single_face_reel(piercing, ReelFace.ResultTier.SUCCESS, 1.0)
	var attack2: CombatResolver.AttackResult = resolver.resolve_single_reel(reel2, 10.0, piercing, 0, 1.0)
	var attack3: CombatResolver.AttackResult = resolver.reresolve_reel(reel2, 10.0, piercing, 0)
	_check(attack2.final_damage == attack3.final_damage, "resolve_single_reel(damage_multiplier=1.0) matches reresolve_reel's own math (got %d vs %d)" % [attack2.final_damage, attack3.final_damage])

	# A miss face (FAILURE) deals no damage regardless of damage_multiplier/flat_damage_bonus.
	var reel4: ActionReel = _make_single_face_reel(piercing, ReelFace.ResultTier.FAILURE, 0.0)
	var attack4: CombatResolver.AttackResult = resolver.resolve_single_reel(reel4, 10.0, piercing, 5, 2.0)
	_check(attack4.final_damage == 0, "a FAILURE face deals no damage even with flat_damage_bonus/damage_multiplier set")

	# Ranger precondition: mark_marksmans_call is a real, pickable talent on the Hunter's Mark row.
	var ranger: Combatant = ClassLibrary.make(&"ranger").build_combatant(true)
	ranger.level = Combatant.MAX_LEVEL
	_check(ranger.pick_ability_talent(&"base_ability", &"mark_marksmans_call"), "picks mark_marksmans_call")
	_check(ranger.has_ability_talent(&"mark_marksmans_call"), "has_ability_talent sees mark_marksmans_call")

	print(("MARKSMAN'S CALL TEST PASSED" if _failures == 0 else "MARKSMAN'S CALL TEST FAILED: %d" % _failures))
	quit(_failures)
