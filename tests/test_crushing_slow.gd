extends SceneTree

# Headless test: a Crushing crit-success reports the Slow rider; ordinary hits do not.
# Also verifies the end-to-end re-sort: applying Slow drops the bearer in get_turn_order().
# Run: Godot_v4.6.3-stable_win64 --headless --path . --script res://tests/test_crushing_slow.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _one_face_reel(tier: ReelFace.ResultTier, mult: float, type: DamageType) -> ActionReel:
	var r: ActionReel = ActionReel.new()
	r.damage_type = type
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = mult
	r.faces.append(f)
	return r

func _initialize() -> void:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	_check(crushing.inherent_rider_id == &"slow", "crushing.tres carries the slow rider id")

	var resolver: CombatResolver = CombatResolver.new()

	# --- Crit-success on a Crushing reel reports the slow rider ---
	var crit_reels: Array[ActionReel] = [_one_face_reel(ReelFace.ResultTier.CRIT_SUCCESS, 2.0, crushing)]
	var crit: Array = resolver.resolve_combat_phase(crit_reels, 8.0, earth)
	_check(crit[0].rider_effect_id == &"slow", "crit-success Crushing -> rider 'slow' (got %s)" % str(crit[0].rider_effect_id))

	# --- An ordinary success does NOT report a rider (rider is crit-only) ---
	var hit_reels: Array[ActionReel] = [_one_face_reel(ReelFace.ResultTier.SUCCESS, 1.0, crushing)]
	var hit: Array = resolver.resolve_combat_phase(hit_reels, 8.0, earth)
	_check(hit[0].rider_effect_id == &"", "plain success Crushing -> no rider (got %s)" % str(hit[0].rider_effect_id))

	# --- End-to-end: applying the rider drops the bearer in turn order ---
	var pc: Combatant = Combatant.new(); pc.display_name = "Martin"; pc.is_player = true; pc.max_hp = 40
	pc.base_initiative = 60; pc.recompute_initiative(); pc.start_combat()
	var enemy: Combatant = Combatant.new(); enemy.display_name = "Rat"; enemy.is_player = false; enemy.max_hp = 30
	enemy.base_initiative = 55; enemy.recompute_initiative(); enemy.start_combat()
	var tm: TurnManager = TurnManager.new(); tm.combatants = [pc, enemy]

	var before: Array[Combatant] = tm.get_turn_order()
	_check(before[0] == pc, "before Slow: Martin (60) acts first")

	pc.attach_effect(EffectLibrary.make(&"slow"))  # 60 - 20 = 40, now below the Rat's 55
	var after: Array[Combatant] = tm.get_turn_order()
	_check(after[0] == enemy, "after Slow: Rat (55) now acts before Martin (40)")
	_check(pc.current_initiative == 40, "Martin slowed to 40 (got %d)" % pc.current_initiative)

	print(("CRUSHING SLOW TEST PASSED" if _failures == 0 else "CRUSHING SLOW TEST FAILED: %d" % _failures))
	quit(_failures)
