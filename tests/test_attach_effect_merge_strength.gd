extends SceneTree

# Headless test for the attach_effect() merge-strength fix (2026-08-24 harvester-talent-tree spec
# §2). Proves that merging an effect sharing an id with an already-active one keeps whichever side
# is STRONGER (dot_base_damage for DAMAGE_OVER_TIME, magnitude for every other Kind), while still
# refreshing duration/stacks from the incoming effect, regardless of merge order.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_attach_effect_merge_strength.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _init() -> void:
	_test_dot_weaker_then_stronger()
	_test_dot_stronger_then_weaker()
	_test_multiplier_edit_weaker_then_stronger()
	_test_duration_and_stacks_still_refresh()
	_test_heal_multiplier_plain_then_withering()
	_test_heal_multiplier_withering_then_plain()
	quit(_failures)

func _test_dot_weaker_then_stronger() -> void:
	var c: Combatant = Combatant.new()
	var weak := Effect.new()
	weak.id = &"cursed"; weak.kind = Effect.Kind.DAMAGE_OVER_TIME; weak.dot_base_damage = 12.0
	weak.duration = 3
	c.attach_effect(weak)
	var strong := Effect.new()
	strong.id = &"cursed"; strong.kind = Effect.Kind.DAMAGE_OVER_TIME; strong.dot_base_damage = 15.0
	strong.duration = 3
	c.attach_effect(strong)
	var merged: Effect = c._find_effect(&"cursed")
	_check(merged != null, "cursed effect present after merge")
	_check(is_equal_approx(merged.dot_base_damage, 15.0), "weaker-then-stronger: kept the STRONGER 15.0 dot_base_damage (got %.1f)" % merged.dot_base_damage)

func _test_dot_stronger_then_weaker() -> void:
	var c: Combatant = Combatant.new()
	var strong := Effect.new()
	strong.id = &"cursed"; strong.kind = Effect.Kind.DAMAGE_OVER_TIME; strong.dot_base_damage = 15.0
	strong.duration = 3
	c.attach_effect(strong)
	var weak := Effect.new()
	weak.id = &"cursed"; weak.kind = Effect.Kind.DAMAGE_OVER_TIME; weak.dot_base_damage = 12.0
	weak.duration = 3
	c.attach_effect(weak)
	var merged: Effect = c._find_effect(&"cursed")
	_check(is_equal_approx(merged.dot_base_damage, 15.0), "stronger-then-weaker: KEEPS the stronger 15.0, doesn't downgrade to 12.0 (got %.1f)" % merged.dot_base_damage)

func _test_multiplier_edit_weaker_then_stronger() -> void:
	var c: Combatant = Combatant.new()
	var weak := Effect.new()
	weak.id = &"sundered"; weak.kind = Effect.Kind.MULTIPLIER_EDIT; weak.magnitude = 1.25
	weak.duration = 2
	c.attach_effect(weak)
	var strong := Effect.new()
	strong.id = &"sundered"; strong.kind = Effect.Kind.MULTIPLIER_EDIT; strong.magnitude = 1.5
	strong.duration = 2
	c.attach_effect(strong)
	var merged: Effect = c._find_effect(&"sundered")
	_check(is_equal_approx(merged.magnitude, 1.5), "non-DoT kind: kept the STRONGER 1.5 magnitude (got %.2f)" % merged.magnitude)

func _test_duration_and_stacks_still_refresh() -> void:
	var c: Combatant = Combatant.new()
	var first := Effect.new()
	first.id = &"cursed"; first.kind = Effect.Kind.DAMAGE_OVER_TIME; first.dot_base_damage = 12.0
	first.duration = 1; first.max_stacks = 3
	c.attach_effect(first)
	var second := Effect.new()
	second.id = &"cursed"; second.kind = Effect.Kind.DAMAGE_OVER_TIME; second.dot_base_damage = 10.0
	second.duration = 5; second.max_stacks = 3
	c.attach_effect(second)
	var merged: Effect = c._find_effect(&"cursed")
	_check(merged.duration == 5, "duration still refreshes to the incoming value even when strength doesn't (got %d)" % merged.duration)
	_check(merged.stacks == 2, "stacks still increments on merge (got %d)" % merged.stacks)
	_check(is_equal_approx(merged.dot_base_damage, 12.0), "weaker second attach doesn't downgrade dot_base_damage (got %.1f)" % merged.dot_base_damage)

## Final-review finding 4 (2026-08-24): heal_multiplier (Task 6, Withering Touch) must merge to
## whichever side is LOWER (more debuffing), the opposite polarity from dot_base_damage/magnitude,
## since 1.0 = no reduction and a lower value is the stronger debuff. Proven both merge orders.
func _test_heal_multiplier_plain_then_withering() -> void:
	var c: Combatant = Combatant.new()
	var plain := Effect.new()
	plain.id = &"cursed"; plain.kind = Effect.Kind.DAMAGE_OVER_TIME; plain.dot_base_damage = 12.0
	plain.duration = 3; plain.heal_multiplier = 1.0
	c.attach_effect(plain)
	var withering := Effect.new()
	withering.id = &"cursed"; withering.kind = Effect.Kind.DAMAGE_OVER_TIME; withering.dot_base_damage = 12.0
	withering.duration = 3; withering.heal_multiplier = 0.5
	c.attach_effect(withering)
	var merged: Effect = c._find_effect(&"cursed")
	_check(is_equal_approx(merged.heal_multiplier, 0.5), "plain(1.0) then Withering(0.5): the stronger 0.5 heal_multiplier survives (got %.2f)" % merged.heal_multiplier)

func _test_heal_multiplier_withering_then_plain() -> void:
	var c: Combatant = Combatant.new()
	var withering := Effect.new()
	withering.id = &"cursed"; withering.kind = Effect.Kind.DAMAGE_OVER_TIME; withering.dot_base_damage = 12.0
	withering.duration = 3; withering.heal_multiplier = 0.5
	c.attach_effect(withering)
	var plain := Effect.new()
	plain.id = &"cursed"; plain.kind = Effect.Kind.DAMAGE_OVER_TIME; plain.dot_base_damage = 12.0
	plain.duration = 3; plain.heal_multiplier = 1.0
	c.attach_effect(plain)
	var merged: Effect = c._find_effect(&"cursed")
	_check(is_equal_approx(merged.heal_multiplier, 0.5), "Withering(0.5) then plain(1.0): does NOT get overwritten back to 1.0 (got %.2f)" % merged.heal_multiplier)
