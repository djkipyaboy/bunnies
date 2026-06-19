class_name MainPhasePlan
extends RefCounted

## The staged, not-yet-committed Main-Phase-1 choices for one combatant's turn
## (DESIGN spec: 2026-06-19-main1-staging-design.md). Toggling a choice only updates a PREVIEW —
## nothing is spent/consumed/applied until [method commit] runs on SPIN. A fresh instance is built
## each turn. Pure logic; the scene renders the preview and owns the buttons.

var combatant: Combatant
var splice_type: DamageType
var splice_cost: int
var reel_cap: int
var wild_reel: int
var wild_spins: int

var splice_staged: bool = false
var fire_ultimate_staged: bool = false

func _init(c: Combatant, p_splice_type: DamageType, p_splice_cost: int = 2, p_reel_cap: int = 5, p_wild_reel: int = 0, p_wild_spins: int = 2) -> void:
	combatant = c
	splice_type = p_splice_type
	splice_cost = p_splice_cost
	reel_cap = p_reel_cap
	wild_reel = p_wild_reel
	wild_spins = p_wild_spins

## True if a splice can be newly STAGED: affordable AND under the reel-cap. Un-staging is always allowed.
func can_stage_splice() -> bool:
	if combatant == null or combatant.resource_pool == null:
		return false
	return combatant.resource_pool.can_afford({&"stamina": splice_cost}) and combatant.turn_reels.size() < reel_cap

## True if the Ultimate can be newly STAGED: the Bonus Meter is armed. Un-staging is always allowed.
func can_stage_ultimate() -> bool:
	return combatant != null and combatant.bonus_meter != null and combatant.bonus_meter.is_armed()

## Un-stages if staged; else stages only when [method can_stage_splice].
func toggle_splice() -> void:
	if splice_staged:
		splice_staged = false
	elif can_stage_splice():
		splice_staged = true

## Un-stages if staged; else stages only when [method can_stage_ultimate].
func toggle_ultimate() -> void:
	if fire_ultimate_staged:
		fire_ultimate_staged = false
	elif can_stage_ultimate():
		fire_ultimate_staged = true

## The reels the spin WOULD use: the committed turn reels plus one staged splice reel (cap-respecting).
## Read-only — never mutates the combatant.
func preview_reels() -> Array[ActionReel]:
	var reels: Array[ActionReel] = combatant.turn_reels.duplicate()
	if splice_staged and reels.size() < reel_cap:
		reels.append(ActionReel.make_default(splice_type))
	return reels

## The Stamina the combatant WOULD have after committing (current minus a staged splice cost).
func preview_stamina() -> int:
	if combatant == null or combatant.resource_pool == null:
		return 0
	var s: int = combatant.resource_pool.stamina
	return (s - splice_cost) if splice_staged else s

## True if committing WOULD consume the Bonus Meter (an Ultimate is staged this turn).
func will_consume_meter() -> bool:
	return fire_ultimate_staged

## The reels that WOULD be wild at spin: already-active carryover wild unioned with a staged fire.
func effective_wild_indices() -> Array[int]:
	var out: Array[int] = combatant.wild_reel_indices().duplicate()
	if fire_ultimate_staged and not (wild_reel in out):
		out.append(wild_reel)
	return out

## Applies the staged choices via the committed Combatant methods. Called once, on SPIN. The methods
## carry their own guards; staging already validated, so they succeed. No-op when nothing is staged.
func commit() -> void:
	if splice_staged:
		combatant.try_splice_reel(splice_type, combatant.weapon.base_damage, splice_cost, reel_cap)
	if fire_ultimate_staged:
		combatant.fire_sticky_wild(wild_reel, wild_spins)
