extends SceneTree

## Default Ultimate/extra-ability (L5/L7/L9) conflict rule (playtest round 3, player request
## 2026-07-07): an extra ability that adds its OWN weapon-attack reel (REEL_ADDING_EXTRA_IDS /
## TWO_REEL_BONUS_EXTRA_IDS — both deal damage) is mutually exclusive with ANY staged Ultimate,
## symmetric last-press-wins. A pure buff/debuff extra ability (no reel of its own) stays usable
## alongside the Ultimate. See MainPhasePlan._ultimate_conflicts_with_extra_ability and memory
## extra-ability-ultimate-conflict-default.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _armed_plan(class_id: StringName, level: int) -> MainPhasePlan:
	var cc: CharacterClass = ClassLibrary.make(class_id)
	var c: Combatant = cc.build_combatant(true)
	c.level = level
	c.resource_pool.stamina = c.resource_pool.max_stamina
	c.resource_pool.mana = c.resource_pool.max_mana
	c.bonus_meter.add_flat(c.bonus_meter.cap)
	return MainPhasePlan.new(c, c.ability_cost, 5, 2)

func _init() -> void:
	# Warrior: Sundering Strike (L5, REEL_ADDING_EXTRA_IDS) vs Wild — reel-adder loses to the Ultimate
	# and vice versa, whichever is staged last wins.
	var warrior_plan: MainPhasePlan = _armed_plan(&"warrior", 5)
	warrior_plan.toggle_extra_ability(&"sundering_strike")
	_check(warrior_plan.staged_extra_ability_id == &"sundering_strike", "sundering_strike stages first")
	warrior_plan.toggle_ultimate()
	_check(warrior_plan.fire_ultimate_staged, "wild stages")
	_check(warrior_plan.staged_extra_ability_id == &"", "staging wild un-stages sundering_strike")

	var warrior_plan2: MainPhasePlan = _armed_plan(&"warrior", 5)
	warrior_plan2.toggle_ultimate()
	_check(warrior_plan2.fire_ultimate_staged, "wild stages first")
	warrior_plan2.toggle_extra_ability(&"sundering_strike")
	_check(warrior_plan2.staged_extra_ability_id == &"sundering_strike", "sundering_strike re-stages")
	_check(not warrior_plan2.fire_ultimate_staged, "staging sundering_strike un-stages wild")

	# Warrior: Heroic Guard (L7, pure buff, no reel) stays usable ALONGSIDE Wild — the default rule
	# only restricts reel-adding extras.
	var warrior_plan3: MainPhasePlan = _armed_plan(&"warrior", 7)
	warrior_plan3.toggle_extra_ability(&"heroic_guard")
	warrior_plan3.toggle_ultimate()
	_check(warrior_plan3.staged_extra_ability_id == &"heroic_guard", "heroic_guard stays staged alongside wild")
	_check(warrior_plan3.fire_ultimate_staged, "wild stays staged alongside heroic_guard")

	# Seer: Mana Surge (L9, TWO_REEL_BONUS_EXTRA_IDS) vs The Big Bang — bonus-reel extras are covered
	# by the same default as the plain reel-adders.
	var seer_plan: MainPhasePlan = _armed_plan(&"seer", 9)
	seer_plan.toggle_extra_ability(&"mana_surge")
	_check(seer_plan.staged_extra_ability_id == &"mana_surge", "mana_surge stages first")
	seer_plan.toggle_ultimate()
	_check(seer_plan.fire_ultimate_staged, "big_bang stages")
	_check(seer_plan.staged_extra_ability_id == &"", "staging big_bang un-stages mana_surge")

	# Seer: Foresight (L7, pure buff — ally shield, no reel) stays usable alongside The Big Bang.
	var seer_plan2: MainPhasePlan = _armed_plan(&"seer", 7)
	seer_plan2.toggle_extra_ability(&"foresight")
	seer_plan2.toggle_ultimate()
	_check(seer_plan2.staged_extra_ability_id == &"foresight", "foresight stays staged alongside big_bang")
	_check(seer_plan2.fire_ultimate_staged, "big_bang stays staged alongside foresight")

	# Ranger: Crippling Shot (L9, REEL_ADDING_EXTRA_IDS) vs Collateral Damage.
	var ranger_plan: MainPhasePlan = _armed_plan(&"ranger", 9)
	ranger_plan.toggle_ultimate()
	_check(ranger_plan.fire_ultimate_staged, "collateral stages first")
	ranger_plan.toggle_extra_ability(&"crippling_shot")
	_check(ranger_plan.staged_extra_ability_id == &"crippling_shot", "crippling_shot re-stages")
	_check(not ranger_plan.fire_ultimate_staged, "staging crippling_shot un-stages collateral")

	quit()
