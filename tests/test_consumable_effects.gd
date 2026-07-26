extends SceneTree

## ConsumableEffects (2026-07-26 out-of-combat item-use design §3) — a static-only helper, mirrors
## TypeVisuals/RarityVisuals. Only the "heal" effect_type is implemented this pass; an unrecognized
## effect_type falls back to a generic, non-crashing message (defensive only — never reachable with
## the one seeded item type today).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_potion(heal_amount: int, effect_type: StringName = &"heal") -> ConsumableItem:
	var item: ConsumableItem = ConsumableItem.new()
	item.display_name = "Healing Potion"
	item.heal_amount = heal_amount
	item.effect_type = effect_type
	return item

func _make_combatant(display_name: String, hp: int, max_hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = display_name
	c.max_hp = max_hp
	c.hp = hp
	return c

func _init() -> void:
	var potion: ConsumableItem = _make_potion(30)
	var basil: Combatant = _make_combatant("Basil", 50, 100)

	var result: String = ConsumableEffects.apply(potion, basil)
	_check(basil.hp == 80, "apply() heals the target by heal_amount")
	_check(result.find("Basil") != -1, "apply() result names the target (got '%s')" % result)
	_check(result.find("30") != -1, "apply() result states the heal amount (got '%s')" % result)

	var desc: String = ConsumableEffects.description(potion, basil)
	_check(desc.find("Basil") != -1, "description() names the current target (got '%s')" % desc)
	_check(desc.find("30") != -1, "description() states the heal amount (got '%s')" % desc)

	var desc_no_target: String = ConsumableEffects.description(potion, null)
	_check(desc_no_target.find("your target") != -1, "description() falls back to 'your target' with no target picked yet (got '%s')" % desc_no_target)

	# Dead ally: heal() itself no-ops (returns 0) on hp <= 0. apply()'s message still states the
	# item's intended heal_amount (matches how the in-combat log already reports intended amounts,
	# not the clipped actual) — this is a deliberate, documented edge case (design §5), not a bug.
	var dead: Combatant = _make_combatant("Fallen", 0, 100)
	var dead_result: String = ConsumableEffects.apply(potion, dead)
	_check(dead.hp == 0, "apply() on a dead ally does not revive them")
	_check(dead_result.find("30") != -1, "apply() on a dead ally still states the item's stated heal_amount (got '%s')" % dead_result)

	# Overheal: apply()'s message states heal_amount even when heal() itself clips (returns overflow).
	var almost_full: Combatant = _make_combatant("Topped Up", 95, 100)
	var overheal_result: String = ConsumableEffects.apply(potion, almost_full)
	_check(almost_full.hp == 100, "apply() clips at max_hp")
	_check(overheal_result.find("30") != -1, "apply()'s message states the intended amount even on overheal (got '%s')" % overheal_result)

	# Unrecognized effect_type: no crash, generic fallback text.
	var mystery: ConsumableItem = _make_potion(30, &"transmute")
	var basil2: Combatant = _make_combatant("Basil", 50, 100)
	var mystery_result: String = ConsumableEffects.apply(mystery, basil2)
	_check(basil2.hp == 50, "an unrecognized effect_type applies no effect")
	_check(mystery_result != "", "an unrecognized effect_type still returns a non-empty fallback message")

	quit()
