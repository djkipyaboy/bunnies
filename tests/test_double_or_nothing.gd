extends SceneTree

## Chancer L9 "Double or Nothing" (spec 2026-07-01, task 22): an ultimate-tier, ALL-IN gamble that
## spends 100% of current Stamina (must have at least 1) for a big 1-spin Empowered — a crit-fail on
## that spin recoils as self-damage, any other non-fail reel refunds Stamina. Covers the two
## headlessly-testable surfaces: Combatant.fire_double_or_nothing() (the all-in cost + Empowered
## attach) and MainPhasePlan.can_stage_extra_ability's special-cased "stamina >= 1" gate (since the
## AbilityDef's own cost is 0 — the real cost is computed at cast time, not staging time).
##
## NOT covered here (and not expected to be — CLAUDE.md §5's hard ceiling): the post-spin
## refund/recoil bookkeeping lives in combat.gd's _apply_attack(), which is orchestrator/scene-level
## (needs a live spin + CombatResolver.AttackResult stream). That path is a manual-playtest item.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"chancer")

	# --- fire_double_or_nothing(): all-in cost + Empowered attach --------------------------------
	var c: Combatant = cc.build_combatant(true)
	c.resource_pool.stamina = 4
	c.resource_pool.max_stamina = 10

	var fired: bool = c.fire_double_or_nothing()
	_check(fired, "fire_double_or_nothing succeeds with stamina > 0")
	_check(c.resource_pool.stamina == 0, "all-in gamble spends 100% of current stamina")
	_check(c.double_or_nothing_pending, "pending flag set after firing")
	_check(c.double_or_nothing_refund_accum == 0, "refund accumulator starts at 0")

	var empowered: Effect = c.active_effects.filter(func(e: Effect) -> bool: return e.id == &"empowered")[0]
	_check(empowered != null, "an empowered effect is attached")
	_check(empowered.magnitude == 1.5, "empowered magnitude is 1.5 (bigger than the base 1.4)")
	_check(empowered.duration == 1, "empowered lasts exactly 1 turn (this spin only)")

	# Stamina is now 0 — no more all-in gambles until regen.
	_check(not c.fire_double_or_nothing(), "fire_double_or_nothing fails when stamina == 0")

	# --- can_stage_extra_ability override: stamina >= 1, ignoring the AbilityDef's cost=0 ---------
	var gate_c: Combatant = cc.build_combatant(true)
	gate_c.level = 9
	var plan: MainPhasePlan = MainPhasePlan.new(gate_c)

	gate_c.resource_pool.stamina = 0
	_check(not plan.can_stage_extra_ability(&"double_or_nothing"), "not stageable at 0 stamina, despite cost=0")

	gate_c.resource_pool.stamina = 1
	_check(plan.can_stage_extra_ability(&"double_or_nothing"), "stageable at 1 stamina regardless of cost=0")

	# Below unlock level: still gated normally even with stamina available.
	gate_c.level = 1
	_check(not plan.can_stage_extra_ability(&"double_or_nothing"), "not stageable below level 9")
	gate_c.level = 9

	# On cooldown: still gated normally even with stamina available.
	gate_c.start_cooldown(&"double_or_nothing", 7)
	_check(not plan.can_stage_extra_ability(&"double_or_nothing"), "not stageable while on cooldown")
	gate_c.cooldowns.clear()

	# --- commit() wiring: toggling + committing calls fire_double_or_nothing via the match arm ----
	var commit_c: Combatant = cc.build_combatant(true)
	commit_c.level = 9
	commit_c.resource_pool.stamina = 5
	var commit_plan: MainPhasePlan = MainPhasePlan.new(commit_c)
	commit_plan.toggle_extra_ability(&"double_or_nothing")
	_check(commit_plan.staged_extra_ability_id == &"double_or_nothing", "toggle stages double_or_nothing")
	commit_plan.commit()
	_check(commit_c.resource_pool.stamina == 0, "commit fired the all-in gamble (spent all stamina)")
	_check(commit_c.double_or_nothing_pending, "commit left the pending flag set for combat.gd to resolve")
	_check(commit_c.is_on_cooldown(&"double_or_nothing"), "commit started the 7-turn cooldown")

	quit()
