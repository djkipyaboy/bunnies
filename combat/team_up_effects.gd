class_name TeamUpEffects
extends RefCounted

## Applies a resolved Team-Up! tally (2026-07-29 spec §5) — the orchestrator half of the
## resolver/orchestrator split TeamUpMinigame.tally() reports. Same-symbol counts collapse into ONE
## combined application per symbol (never per-face); Surge is payline-gated only (a raw surge count
## in the tally is otherwise inert — only tally["surge_lines"] matters here). All [ASSUMPTION]
## magnitudes, tune by playtest (CLAUDE.md §4).

const STRIKE_PER_SYMBOL: int = 8
const MEND_PER_SYMBOL: int = 8
const WARD_PER_SYMBOL: int = 8
const WARD_SHIELD_TURNS: int = 2
const BREAK_BASE_DURATION: int = 2
const SURGE_AMPLIFY_PER_LINE: float = 0.5   ## each completed Surge payline adds +50%, additive stacking

## [param tally]: from TeamUpMinigame.tally(). [param allies]/[param enemies]: plain Combatant
## arrays (combat.gd passes _allies_of(attacker)/_enemies_of(attacker)). [param damage_type]: the
## Team-Up round's damage type (Light for the one authored region so far).
static func apply(tally: Dictionary, allies: Array, enemies: Array, damage_type: DamageType) -> void:
	var amp: float = 1.0 + float(tally.get("surge_lines", 0)) * SURGE_AMPLIFY_PER_LINE

	var strike_count: int = tally.get("strike", 0)
	if strike_count > 0:
		var raw: int = ceili(strike_count * STRIKE_PER_SYMBOL * amp)
		for enemy: Combatant in enemies:
			if enemy.is_alive():
				var mult: float = damage_type.multiplier_against(enemy.defense_type) if damage_type != null else 1.0
				enemy.take_damage(ceili(raw * mult))

	var mend_count: int = tally.get("mend", 0)
	if mend_count > 0:
		var heal_amt: int = ceili(mend_count * MEND_PER_SYMBOL * amp)
		for ally: Combatant in allies:
			if ally.is_alive():
				ally.heal(heal_amt)

	var ward_count: int = tally.get("ward", 0)
	if ward_count > 0:
		var shield_amt: int = ceili(ward_count * WARD_PER_SYMBOL * amp)
		for ally: Combatant in allies:
			if ally.is_alive():
				ally.apply_shield(shield_amt, WARD_SHIELD_TURNS)

	var break_count: int = tally.get("break", 0)
	if break_count > 0:
		var duration: int = BREAK_BASE_DURATION + (break_count - 1)
		for enemy: Combatant in enemies:
			if enemy.is_alive():
				var eff: Effect = EffectLibrary.make(&"weakened")
				eff.duration = duration
				enemy.attach_effect(eff)
