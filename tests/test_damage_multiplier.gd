extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	_check(is_equal_approx(c.outgoing_damage_multiplier(), 1.0), "no effects -> outgoing 1.0")
	_check(is_equal_approx(c.incoming_damage_multiplier(), 1.0), "no effects -> incoming 1.0")

	var emp: Effect = Effect.new()
	emp.id = &"empowered"; emp.kind = Effect.Kind.MULTIPLIER_EDIT; emp.magnitude = 1.5
	emp.affects_incoming = false; emp.beneficial = true; emp.duration = 2
	c.attach_effect(emp)
	_check(is_equal_approx(c.outgoing_damage_multiplier(), 1.5), "empowered raises outgoing to 1.5")
	_check(is_equal_approx(c.incoming_damage_multiplier(), 1.0), "empowered does not affect incoming")

	var guard: Effect = Effect.new()
	guard.id = &"guarded"; guard.kind = Effect.Kind.MULTIPLIER_EDIT; guard.magnitude = 0.5
	guard.affects_incoming = true; guard.beneficial = true; guard.duration = 2
	c.attach_effect(guard)
	_check(is_equal_approx(c.incoming_damage_multiplier(), 0.5), "guarded halves incoming")

	var resolver: CombatResolver = CombatResolver.new()
	var reel: ActionReel = ActionReel.new()
	reel.faces = [ReelFace.new()]
	reel.faces[0].result_tier = ReelFace.ResultTier.SUCCESS
	reel.faces[0].multiplier = 1.0
	var attack: CombatResolver.AttackResult = resolver._resolve_single(reel, 10.0, null, false, 0, 2.0)
	_check(attack.final_damage == 20, "damage_multiplier 2.0 doubles a 10-base success hit")
	quit()
