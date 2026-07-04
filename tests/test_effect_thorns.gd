extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	_check(is_equal_approx(c.thorns_pct(), 0.0), "no effects -> 0 thorns")
	var bastion: Effect = Effect.new()
	bastion.id = &"guarded"; bastion.kind = Effect.Kind.MULTIPLIER_EDIT; bastion.magnitude = 0.5
	bastion.affects_incoming = true; bastion.beneficial = true; bastion.duration = 3
	bastion.thorns_pct = 0.2
	c.attach_effect(bastion)
	_check(is_equal_approx(c.thorns_pct(), 0.2), "guarded-with-thorns reports 0.2")
	quit()
