extends SceneTree

## Warden L9 "Bastion" (spec/task 31): a self-cast, NO-reel, ultimate-tier extra ability (4-turn CD)
## that grants a heavy Guarded (incoming ×0.5) with Thorns (0.20) baked onto the SAME effect instance,
## plus a Taunt — all for 3 turns. Like Mountain Stance (task 16) it only exercises the shared commit()
## dispatch; it does NOT touch REEL_ADDING_EXTRA_IDS/preview_reels. The Thorns-on-Guarded coupling is
## what distinguishes it from Mountain Stance (which stacks immunities instead).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"warden")

	# Below unlock level: not stageable even though everything else is fine.
	var early_c: Combatant = cc.build_combatant(true)
	early_c.level = 1
	var early_plan: MainPhasePlan = MainPhasePlan.new(early_c)
	_check(not early_plan.can_stage_extra_ability(&"bastion"), "not stageable below level 9")

	var c: Combatant = cc.build_combatant(true)
	c.level = 9
	c.resource_pool.mana = c.resource_pool.max_mana
	var starting_mana: int = c.resource_pool.mana

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"bastion"), "stageable at level 9, affordable, no CD")

	plan.toggle_extra_ability(&"bastion")
	_check(plan.staged_extra_ability_id == &"bastion", "toggle stages bastion")

	var before_reel_count: int = c.turn_reels.size()
	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff)")
	_check(c.has_effect(&"guarded"), "commit attaches Guarded")
	_check(c.has_effect(&"taunt"), "commit attaches Taunt")
	var def: AbilityDef = c.find_extra_ability(&"bastion")
	_check(c.resource_pool.mana == starting_mana - def.cost, "commit spent the ability's mana cost (6)")
	_check(c.is_on_cooldown(&"bastion"), "commit put the L9 ability on cooldown")

	# Heavy Guarded: incoming damage is halved (magnitude overridden to 0.5, not the 0.75 default).
	_check(is_equal_approx(c.incoming_damage_multiplier(), 0.5), "incoming_damage_multiplier == 0.5 (heavy Guarded)")

	# Thorns baked onto the SAME guard effect instance: bearer reflects 0.20 of damage taken.
	_check(is_equal_approx(c.thorns_pct(), 0.2), "thorns_pct == 0.2 (Thorns baked onto Guarded)")

	# Direct Combatant-method checks.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.mana = direct_c.resource_pool.max_mana
	var direct_before: int = direct_c.resource_pool.mana
	_check(direct_c.apply_bastion(6), "apply_bastion succeeds when affordable")
	_check(direct_c.has_effect(&"guarded") and direct_c.has_effect(&"taunt"), "apply_bastion attached Guarded + Taunt")
	_check(direct_c.resource_pool.mana == direct_before - 6, "apply_bastion spent 6 mana")
	_check(is_equal_approx(direct_c.incoming_damage_multiplier(), 0.5), "direct: incoming multiplier 0.5")
	_check(is_equal_approx(direct_c.thorns_pct(), 0.2), "direct: thorns_pct 0.2")

	# Affordability: 0 mana -> refused, no change.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.resource_pool.mana = 0
	_check(not poor_c.apply_bastion(6), "apply_bastion fails when unaffordable")
	_check(not poor_c.has_effect(&"guarded"), "no Guarded attached on a failed (unaffordable) cast")

	quit()
