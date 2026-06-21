class_name MainPhasePlan
extends RefCounted

## The staged, not-yet-committed Main-Phase-1 choices for one combatant's turn
## (spec 2026-06-19-main1-staging; generalized 2026-06-21 for per-class base abilities, spec §4A).
## Toggling only updates a PREVIEW — nothing is spent/applied until [method commit] on SPIN. A fresh
## instance is built each turn. Pure logic; the scene renders the preview and owns the buttons.
##
## The base ability is read from [member Combatant.ability_id]:
##   • &"flurry" — splice +1 own-type reel (a normal extra swing). Skirmisher.
##   • &"rend"   — splice +1 own-type REND reel (no direct damage; applies BLEED on a hit). Warrior.
##   • &"heft"   — edit this turn's reels (one FAILURE→SUCCESS each). Vanguard. Does not add a reel.

var combatant: Combatant
var ability_id: StringName
var ability_cost: int
var reel_cap: int
var wild_spins: int

var ability_staged: bool = false
var fire_ultimate_staged: bool = false

func _init(c: Combatant, p_ability_cost: int = 2, p_reel_cap: int = 5, p_wild_spins: int = 2) -> void:
	combatant = c
	ability_id = c.ability_id if c != null else &""
	ability_cost = p_ability_cost
	reel_cap = p_reel_cap
	wild_spins = p_wild_spins

## Whether this ability adds a reel to the attacker's own loadout (previewable as an extra strip).
func _ability_adds_reel() -> bool:
	return ability_id == &"flurry" or ability_id == &"rend"

## True if the ability can be newly STAGED: there IS an ability, it's affordable, and (for reel-adding
## abilities) the loadout is under the cap. Un-staging is always allowed.
func can_stage_ability() -> bool:
	if combatant == null or combatant.resource_pool == null or ability_id == &"":
		return false
	if not combatant.resource_pool.can_afford({&"stamina": ability_cost}):
		return false
	if _ability_adds_reel() and combatant.turn_reels.size() >= reel_cap:
		return false
	return true

## True if the Ultimate can be newly STAGED: the Bonus Meter is armed. Un-staging is always allowed.
func can_stage_ultimate() -> bool:
	return combatant != null and combatant.bonus_meter != null and combatant.bonus_meter.is_armed()

func toggle_ability() -> void:
	if ability_staged:
		ability_staged = false
	elif can_stage_ability():
		ability_staged = true

func toggle_ultimate() -> void:
	if fire_ultimate_staged:
		fire_ultimate_staged = false
	elif can_stage_ultimate():
		fire_ultimate_staged = true

## The reels the spin WOULD use. A staged reel-adding ability (flurry/rend) appends a previewed
## own-type reel (rend's preview reel is a no-damage BLEED reel). Heft edits faces in place on commit,
## so it does not change the previewed COUNT. Read-only — never mutates the combatant.
func preview_reels() -> Array[ActionReel]:
	var reels: Array[ActionReel] = combatant.turn_reels.duplicate()
	if ability_staged and _ability_adds_reel() and reels.size() < reel_cap:
		match ability_id:
			&"flurry":
				reels.append(ActionReel.make_default(combatant.weapon_type()))
			&"rend":
				reels.append(ActionReel.make_rend(combatant.weapon_type()))
	return reels

## The Stamina the combatant WOULD have after committing (current minus a staged ability cost).
func preview_stamina() -> int:
	if combatant == null or combatant.resource_pool == null:
		return 0
	var s: int = combatant.resource_pool.stamina
	return (s - ability_cost) if ability_staged else s

## True if committing WOULD consume the Bonus Meter (an Ultimate is staged this turn).
func will_consume_meter() -> bool:
	return fire_ultimate_staged

## The reels that WOULD be wild at spin: already-active carryover wild unioned with a staged fire.
func effective_wild_indices() -> Array[int]:
	var out: Array[int] = combatant.wild_reel_indices().duplicate()
	if fire_ultimate_staged:
		for i: int in range(_weapon_reel_count()):
			if not (i in out):
				out.append(i)
		out.sort()
	return out

## How many WEAPON reels the Ultimate would make wild (splices/ability reels excluded).
func _weapon_reel_count() -> int:
	if combatant == null or combatant.weapon == null:
		return 0
	return combatant.weapon.reels.size()

## Applies the staged choices via committed Combatant methods. Called once, on SPIN. The methods
## carry their own guards; staging already validated, so they succeed. No-op when nothing is staged.
func commit() -> void:
	if ability_staged:
		match ability_id:
			&"flurry":
				combatant.try_splice_reel(combatant.weapon_type(), combatant.weapon.base_damage, ability_cost, reel_cap)
			&"rend":
				combatant.try_rend_reel(combatant.weapon_type(), ability_cost, reel_cap)
			&"heft":
				combatant.apply_heft(ability_cost)
	if fire_ultimate_staged:
		combatant.fire_sticky_wild(_weapon_reel_count(), wild_spins)
