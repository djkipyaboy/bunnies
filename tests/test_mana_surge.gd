extends SceneTree

## Seer L9 "Mana Surge" (task 28): a self-cast, NO-reel, ultimate-tier extra ability (4-turn CD)
## that attaches a massive Empowered (+60%, duration 1) to this turn's own reels only. Like
## Riposte Storm (task 19) / Mountain Stance (task 16) it only exercises the shared commit()
## dispatch — it does NOT touch REEL_ADDING_EXTRA_IDS/preview_reels (adds no reel). Spends MANA,
## not stamina (Seer is mana-only).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"seer")

	# Below unlock level: not stageable even though everything else is fine.
	var early_c: Combatant = cc.build_combatant(true)
	early_c.level = 7
	var early_plan: MainPhasePlan = MainPhasePlan.new(early_c)
	_check(not early_plan.can_stage_extra_ability(&"mana_surge"), "not stageable below level 9")

	var c: Combatant = cc.build_combatant(true)
	c.level = 9
	c.resource_pool.mana = c.resource_pool.max_mana
	var starting_mana: int = c.resource_pool.mana

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"mana_surge"), "stageable at level 9, affordable, no CD")

	plan.toggle_extra_ability(&"mana_surge")
	_check(plan.staged_extra_ability_id == &"mana_surge", "toggle stages mana_surge")

	var before_reel_count: int = c.turn_reels.size()
	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (self-cast buff)")
	_check(c.has_effect(&"empowered"), "commit attaches Empowered")
	_check(is_equal_approx(c.outgoing_damage_multiplier(), 1.6), "outgoing_damage_multiplier == 1.6 right after commit")
	var def: AbilityDef = c.find_extra_ability(&"mana_surge")
	_check(c.resource_pool.mana == starting_mana - def.cost, "commit spent the ability's mana cost (6)")
	_check(c.is_on_cooldown(&"mana_surge"), "commit put the L9 ability on cooldown (4 turns)")

	# duration 1: one on_end() tick expires it (tick_effects() decrements duration and removes it).
	c.on_end()
	_check(not c.has_effect(&"empowered"), "on_end expired the duration-1 Empowered")
	_check(is_equal_approx(c.outgoing_damage_multiplier(), 1.0), "outgoing_damage_multiplier back to 1.0 after expiry")

	# Direct Combatant-method checks.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.mana = direct_c.resource_pool.max_mana
	var direct_before: int = direct_c.resource_pool.mana
	_check(direct_c.apply_mana_surge(6), "apply_mana_surge succeeds when affordable")
	_check(direct_c.has_effect(&"empowered"), "apply_mana_surge attached Empowered")
	_check(direct_c.resource_pool.mana == direct_before - 6, "apply_mana_surge spent 6 mana")
	_check(is_equal_approx(direct_c.outgoing_damage_multiplier(), 1.6), "direct: outgoing multiplier 1.6")

	# Affordability: 0 mana -> refused, no change.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.resource_pool.mana = 0
	_check(not poor_c.apply_mana_surge(6), "apply_mana_surge fails when unaffordable")
	_check(not poor_c.has_effect(&"empowered"), "no Empowered attached on a failed (unaffordable) cast")

	quit()
