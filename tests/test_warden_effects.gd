extends SceneTree

## Headless test for the Hollow Warden's 2 new effects (spec 2026-07-19 §3.1): warden_curse (a FLAT
## stacking party-wide DoT, unlike every existing weapon-derived DoT) and indestructible (blocks
## direct damage via the existing MULTIPLIER_EDIT mechanism, leaves DoT ticks untouched). Also proves
## the new Combatant.remove_effect() removes an unexpired effect early.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var curse: Effect = EffectLibrary.make(&"warden_curse")
	_check(curse != null, "warden_curse resolves to a real Effect")
	_check(curse.kind == Effect.Kind.DAMAGE_OVER_TIME, "warden_curse is a DoT")
	_check(curse.max_stacks == 3, "warden_curse stacks up to 3")
	_check(curse.dot_fractions == [4.0, 7.0, 10.0], "warden_curse fractions are [4.0, 7.0, 10.0]")
	_check(curse.duration == 3, "warden_curse lasts 3 turns per stack")
	_check(not curse.beneficial, "warden_curse is a debuff")
	curse.dot_base_damage = 1.0  # the flat baseline this project's orchestrator seeds at apply time
	_check(curse.dot_damage() == 4, "1 stack of warden_curse deals 4 (flat, not weapon-scaled)")
	curse.add_stack()
	_check(curse.dot_damage() == 7, "2 stacks of warden_curse deals 7")
	curse.add_stack()
	_check(curse.dot_damage() == 10, "3 stacks of warden_curse deals 10 (cap)")

	var indestructible: Effect = EffectLibrary.make(&"indestructible")
	_check(indestructible != null, "indestructible resolves to a real Effect")
	_check(indestructible.kind == Effect.Kind.MULTIPLIER_EDIT, "indestructible is a MULTIPLIER_EDIT")
	_check(indestructible.magnitude == 0.0, "indestructible's magnitude is 0.0 (blocks all direct damage)")
	_check(indestructible.affects_incoming, "indestructible affects INCOMING damage")
	_check(indestructible.beneficial, "indestructible is beneficial (from the boss's own perspective)")

	var c: Combatant = Combatant.new()
	c.attach_effect(indestructible)
	_check(c.incoming_damage_multiplier() == 0.0, "a combatant with indestructible has incoming_damage_multiplier() == 0.0")
	_check(c.dot_damage_multiplier() > 0.0, "indestructible does NOT affect dot_damage_multiplier() — DoT still applies")

	# Two independent effects to prove remove_effect only removes the named one.
	c.attach_effect(EffectLibrary.make(&"guarded"))
	_check(c.has_effect(&"indestructible"), "indestructible is active before removal")
	_check(c.has_effect(&"guarded"), "guarded is active before removal")
	c.remove_effect(&"indestructible")
	_check(not c.has_effect(&"indestructible"), "remove_effect() removes indestructible")
	_check(c.has_effect(&"guarded"), "remove_effect() leaves guarded untouched")
	_check(c.incoming_damage_multiplier() != 0.0, "incoming_damage_multiplier() is no longer 0.0 once indestructible is removed")
	c.remove_effect(&"nonexistent_id")
	_check(c.has_effect(&"guarded"), "remove_effect() on a nonexistent id is a harmless no-op")

	print(("WARDEN EFFECTS TEST PASSED" if _failures == 0 else "WARDEN EFFECTS TEST FAILED: %d" % _failures))
	quit(_failures)
