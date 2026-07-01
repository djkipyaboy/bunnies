extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var ids: Array[StringName] = [&"sundered", &"weakened", &"jinxed", &"rooted", &"guarded", &"taunt", &"empowered", &"evasion", &"regen", &"cursed", &"haste"]
	for id in ids:
		var e: Effect = EffectLibrary.make(id)
		_check(e != null, "EffectLibrary.make(%s) returns non-null" % id)
		_check(e.id == id, "%s: id round-trips" % id)

	var sundered: Effect = EffectLibrary.make(&"sundered")
	_check(sundered.kind == Effect.Kind.MULTIPLIER_EDIT and sundered.affects_incoming and not sundered.beneficial, "sundered: incoming debuff multiplier")
	var guarded: Effect = EffectLibrary.make(&"guarded")
	_check(guarded.kind == Effect.Kind.MULTIPLIER_EDIT and guarded.affects_incoming and guarded.beneficial, "guarded: incoming buff multiplier")
	var empowered: Effect = EffectLibrary.make(&"empowered")
	_check(empowered.kind == Effect.Kind.MULTIPLIER_EDIT and not empowered.affects_incoming and empowered.beneficial, "empowered: outgoing buff multiplier")
	var rooted: Effect = EffectLibrary.make(&"rooted")
	_check(rooted.kind == Effect.Kind.INITIATIVE_MOD and rooted.magnitude < -20.0, "rooted: heavier init hit than slow tier 1")
	var haste: Effect = EffectLibrary.make(&"haste")
	_check(haste.kind == Effect.Kind.INITIATIVE_MOD and haste.magnitude > 0.0 and haste.beneficial, "haste: positive init, beneficial")
	var regen: Effect = EffectLibrary.make(&"regen")
	_check(regen.kind == Effect.Kind.DAMAGE_OVER_TIME and regen.beneficial, "regen: beneficial DoT (heal)")
	var cursed: Effect = EffectLibrary.make(&"cursed")
	_check(cursed.kind == Effect.Kind.DAMAGE_OVER_TIME and not cursed.beneficial, "cursed: debuff DoT")
	quit()
