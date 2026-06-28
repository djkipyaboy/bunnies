class_name EnemyAI
extends RefCounted

## First-iteration enemy targeting policy (spec 2026-06-28 §3.1). Pure + static so it's unit-testable
## without a scene and a future policy swaps only this. Prefers a super-effective matchup, then a
## neutral one, then (only resisted left) attacks anyway; within the chosen tier the lowest-HP PC wins,
## which is also the tie-break. The orchestrator (combat.gd) owns ability use + the actual attack.

## Returns the living PC this [param attacker] should hit, or null if none are alive.
static func pick_target(attacker: Combatant, pcs: Array[Combatant]) -> Combatant:
	if attacker == null or attacker.weapon_type() == null:
		return null
	var atk: DamageType = attacker.weapon_type()
	var supereff: Array[Combatant] = []
	var neutral: Array[Combatant] = []
	var resisted: Array[Combatant] = []
	for pc: Combatant in pcs:
		if pc == null or not pc.is_alive():
			continue
		var m: float = atk.multiplier_against(pc.defense_type)
		if m > 1.0 and not is_equal_approx(m, 1.0):
			supereff.append(pc)
		elif is_equal_approx(m, 1.0):
			neutral.append(pc)
		else:
			resisted.append(pc)
	var tier: Array[Combatant] = supereff if not supereff.is_empty() else (neutral if not neutral.is_empty() else resisted)
	return _lowest_hp(tier)

## Lowest current-HP combatant in [param cands] (ties -> first in order). Null if empty.
static func _lowest_hp(cands: Array[Combatant]) -> Combatant:
	var best: Combatant = null
	for c: Combatant in cands:
		if best == null or c.hp < best.hp:
			best = c
	return best
