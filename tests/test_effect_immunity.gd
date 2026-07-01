extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	var guard: Effect = Effect.new()
	guard.id = &"mountain_stance"; guard.kind = Effect.Kind.MULTIPLIER_EDIT; guard.magnitude = 0.5
	guard.duration = 3; guard.beneficial = true
	guard.immune_effect_ids = [&"slow", &"rooted"]
	guard.grants_stun_immunity = true
	c.attach_effect(guard)

	var slow: Effect = EffectLibrary.make(&"slow")
	c.attach_effect(slow)
	_check(not c.has_effect(&"slow"), "immune_effect_ids blocks slow while active")

	c.base_initiative = 0
	c.stunned_last_turn = false
	var stunned: bool = c.evaluate_stun(50)
	_check(not stunned, "grants_stun_immunity blocks evaluate_stun even with low initiative")

	c.active_effects.clear()  # immunity gone
	c.attach_effect(EffectLibrary.make(&"slow"))
	_check(c.has_effect(&"slow"), "slow attaches normally once immunity is gone")
	quit()
