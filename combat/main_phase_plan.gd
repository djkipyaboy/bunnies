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
##   • &"heft"   — edit this turn's reels (both failures + crit-failure → SUCCESS, i.e. all misses
##                 removed). Vanguard. Does not add a reel.

var combatant: Combatant
var ability_id: StringName
var ultimate_id: StringName
var ability_cost: int
var reel_cap: int
var wild_spins: int

## How many miss→hit conversions the Vanguard Rampage Ultimate applies per reel (matches Heft:
## 2 failures + the crit-failure → all misses removed on each reel).
const RAMPAGE_CONVERSIONS: int = 3
## Rampage is a single-turn Ultimate (AoE for the fired spin only).
const RAMPAGE_SPINS: int = 1
## Collateral Damage (Ranger) is a single-turn Ultimate (+1 reel, splash for the fired spin only).
const COLLATERAL_SPINS: int = 1
## The Big Bang (Seer) tops the loadout to 4 crit-biased WILD reels for one AoE spin (spec 2026-06-27 §4).
const BIG_BANG_REELS: int = 4
const BIG_BANG_SPINS: int = 1
## Earthquake (Warden) is a single-turn Ultimate (+1 WILD reel, splash + stun for the fired spin only).
const EARTHQUAKE_SPINS: int = 1
## Crit-bias WILD spin counts, separated per class (spec 2026-06-21 iteration 2):
## the Warrior's &"wild" is single-spin; the Skirmisher's &"sticky_wild" rides for two.
const WILD_SPINS: int = 1
const STICKY_WILD_SPINS: int = 2

var ability_staged: bool = false
var fire_ultimate_staged: bool = false

## Seer "Select your Fate!" chosen damage type (spec 2026-06-27 §3). Set by [method stage_select_fate]
## (the orchestrator's 6-button type-picker modal); consumed by [method commit]. Null = not chosen.
var selected_fate_type: DamageType = null

func _init(c: Combatant, p_ability_cost: int = 2, p_reel_cap: int = 5, p_wild_spins: int = 2) -> void:
	combatant = c
	ability_id = c.ability_id if c != null else &""
	ultimate_id = c.ultimate_id if c != null else &"sticky_wild"
	ability_cost = p_ability_cost
	reel_cap = p_reel_cap
	wild_spins = p_wild_spins

## The cost dictionary for this combatant's base ability (amount on its declared rail).
func _ability_cost_dict() -> Dictionary:
	var res: StringName = combatant.ability_resource if combatant != null else &"stamina"
	return {res: ability_cost}

## Whether this ability adds a reel to the attacker's own loadout (previewable as an extra strip).
## Select your Fate adds a reel too — and unlike Flurry/Rend its reel JOINS the payline grid.
func _ability_adds_reel() -> bool:
	return ability_id == &"flurry" or ability_id == &"rend" or ability_id == &"select_fate" or ability_id == &"rallying_cry"

## True if the ability can be newly STAGED: there IS an ability, it's affordable, and (for reel-adding
## abilities) the loadout is under the cap. Un-staging is always allowed.
func can_stage_ability() -> bool:
	if ability_locked_by_ultimate():
		return false  # disabled while the Ultimate is staged (UI greys the toggle)
	if combatant == null or combatant.resource_pool == null or ability_id == &"":
		return false
	if not combatant.resource_pool.can_afford(_ability_cost_dict()):
		return false
	if _ability_adds_reel() and combatant.turn_reels.size() >= reel_cap:
		return false
	return true

## True if the Ultimate can be newly STAGED: the Bonus Meter is armed. Un-staging is always allowed.
func can_stage_ultimate() -> bool:
	return combatant != null and combatant.bonus_meter != null and combatant.bonus_meter.is_armed()

## True when the active Ultimate is a crit-bias WILD variant (Warrior 1-spin / Skirmisher 2-spin sticky).
func _is_wild_ultimate() -> bool:
	return ultimate_id == &"wild" or ultimate_id == &"sticky_wild"

## True when the Rampage Ultimate would include the Heft base ability (the Vanguard pairing).
func _rampage_includes_heft() -> bool:
	return ultimate_id == &"rampage" and ability_id == &"heft"

## True when the staged Ultimate ALREADY performs the base ability, so staging both would waste the
## player's resource. Rampage bakes in Heft (the free/coupled case); Wildcard Gamble re-rolls EVERY
## reel, which subsumes the single-reel Re-roll. Every other Ultimate (Warrior Wild + Rend, Ranger
## Collateral + Hunter's Mark, Skirmisher Sticky Wild + Flurry) leaves the base ability independently
## useful, so it stays available ALONGSIDE the Ultimate (player request 2026-06-26).
func _ultimate_subsumes_ability() -> bool:
	if ultimate_id == &"rampage" and ability_id == &"heft":
		return true
	if ultimate_id == &"wildcard_gamble" and ability_id == &"reroll":
		return true
	# The Big Bang carries its OWN type picker (free) and tops to 4 reels, so it fully covers Select your
	# Fate (the paid +1-reel/retype ability). Staging both would just waste 6 mana — lock the base ability
	# out and let the Ultimate's picker choose the spin's type (player request 2026-06-26).
	if ultimate_id == &"big_bang" and ability_id == &"select_fate":
		return true
	return false

## True while the base ability (Heft) is provided FREE by a staged Rampage — toggled on, no Stamina.
func ability_is_free() -> bool:
	return fire_ultimate_staged and _rampage_includes_heft()

## True when a staged Ultimate locks OUT the base ability. Only Ultimates that SUBSUME the ability lock
## it (Chancer's Gamble over Re-roll) — taking both there just wastes the resource. Rampage's Heft is
## "free" (ability_is_free), not "locked". Ultimates that don't include the ability never lock it, so
## Warrior/Ranger/Skirmisher can fire their Ultimate AND use their base ability (pillar §4 trade-offs).
func ability_locked_by_ultimate() -> bool:
	return fire_ultimate_staged and ability_id != &"" and _ultimate_subsumes_ability() and not ability_is_free()

func toggle_ability() -> void:
	if ability_is_free() or ability_locked_by_ultimate():
		return  # ability is controlled by the Ultimate toggle (included by Rampage, or locked out)
	if ability_staged:
		ability_staged = false
		selected_fate_type = null  # clear any Seer type choice on un-stage
	elif ability_id == &"select_fate":
		return  # Select your Fate needs a type choice — staged via stage_select_fate (the type-picker modal)
	elif can_stage_ability():
		ability_staged = true

## Stages Select your Fate! with a player-chosen damage type (from the orchestrator's type-picker modal).
## No-op unless this is the Seer's ability and it can currently be staged.
func stage_select_fate(type: DamageType) -> void:
	if ability_id != &"select_fate" or type == null:
		return
	if can_stage_ability():
		selected_fate_type = type
		ability_staged = true

## Stages The Big Bang with a player-chosen damage type (from the Ultimate's type-picker modal — the same
## 6-type chooser as Select your Fate, but free). No-op unless this is the Seer's big_bang and it's armed.
func stage_big_bang(type: DamageType) -> void:
	if ultimate_id != &"big_bang" or type == null:
		return
	if can_stage_ultimate():
		selected_fate_type = type
		fire_ultimate_staged = true
		if _ultimate_subsumes_ability():
			ability_staged = false   # Big Bang provides type choice + reels — don't also pay Select your Fate

func toggle_ultimate() -> void:
	if fire_ultimate_staged:
		fire_ultimate_staged = false
		if ultimate_id == &"big_bang":
			selected_fate_type = null   # clear the Big Bang type choice on un-stage
		if _rampage_includes_heft():
			ability_staged = false   # untoggling Rampage untoggles the coupled Heft
	elif can_stage_ultimate():
		fire_ultimate_staged = true
		if _rampage_includes_heft():
			ability_staged = true    # toggling Rampage auto-toggles Heft (free, included)
		elif _ultimate_subsumes_ability():
			ability_staged = false   # the Ultimate already does it — drop the staged ability (no waste)
		# else: leave the base ability as the player staged it — it's usable alongside this Ultimate

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
			&"select_fate":
				reels.append(ActionReel.make_default(selected_fate_type))  # joins paylines (a weapon-attack reel)
			&"rallying_cry":
				reels.append(ActionReel.make_rallying_cry(combatant.weapon_type()))  # utility reel (out of paylines, tail)
	# The reel-adding Ultimates preview their +1 attack reel too: Rampage (Heft/AoE aren't strips),
	# Collateral (the splash isn't a strip), and Earthquake (+1 WILD attack reel). All add one own-type
	# weapon-attack reel. Insert BEFORE any trailing utility reel (e.g. a staged Rallying Cry) so the
	# weapon-attack run stays contiguous (matching the commit-time insert).
	if fire_ultimate_staged and (ultimate_id == &"rampage" or ultimate_id == &"collateral" or ultimate_id == &"earthquake") and reels.size() < reel_cap:
		var pos: int = 0
		for i: int in range(reels.size()):
			if reels[i].is_weapon_attack:
				pos = i + 1
		reels.insert(pos, ActionReel.make_default(combatant.weapon_type()))
	# The Big Bang tops the loadout up to 4 reels (the Seer's 2 → 4) — preview the added strips.
	if fire_ultimate_staged and ultimate_id == &"big_bang":
		while reels.size() < mini(BIG_BANG_REELS, reel_cap):
			reels.append(ActionReel.make_default(combatant.weapon_type()))
	return reels

## The combatant's value on the ABILITY's rail after committing (current minus a staged cost).
func preview_resource() -> int:
	if combatant == null or combatant.resource_pool == null:
		return 0
	var res: StringName = combatant.ability_resource
	var cur: int = combatant.resource_pool.mana if res == &"mana" else combatant.resource_pool.stamina
	return (cur - ability_cost) if (ability_staged and not ability_is_free()) else cur

## Back-compat alias used by the current UI (stamina-only classes). Returns preview_resource().
func preview_stamina() -> int:
	return preview_resource()

## True if committing WOULD consume the Bonus Meter (an Ultimate is staged this turn).
func will_consume_meter() -> bool:
	return fire_ultimate_staged

## The reels that WOULD be wild at spin: already-active carryover wild unioned with a staged fire.
func effective_wild_indices() -> Array[int]:
	var out: Array[int] = combatant.wild_reel_indices().duplicate()
	# Only the crit-bias WILD Ultimates (Warrior &"wild" / Skirmisher &"sticky_wild") glow; Rampage doesn't.
	if fire_ultimate_staged and _is_wild_ultimate():
		for i: int in range(_weapon_reel_count()):
			if not (i in out):
				out.append(i)
		out.sort()
	# The Big Bang makes ALL of its (topped-up) reels wild — glow every previewed strip up to 4.
	elif fire_ultimate_staged and ultimate_id == &"big_bang":
		var n: int = mini(BIG_BANG_REELS, preview_reels().size())
		for i: int in range(n):
			if not (i in out):
				out.append(i)
		out.sort()
	# Earthquake makes every weapon-attack reel WILD — glow the leading attack run (the previewed
	# weapon-attack reels; the trailing utility reel is excluded).
	elif fire_ultimate_staged and ultimate_id == &"earthquake":
		var preview: Array[ActionReel] = preview_reels()
		for i: int in range(preview.size()):
			if preview[i].is_weapon_attack and not (i in out):
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
	# When Heft is free-via-Rampage, skip the paid ability commit — fire_rampage applies the Heft itself.
	if ability_staged and not ability_is_free():
		match ability_id:
			&"flurry":
				combatant.try_splice_reel(combatant.weapon_type(), combatant.weapon.base_damage, ability_cost, reel_cap)
			&"rend":
				combatant.try_rend_reel(combatant.weapon_type(), ability_cost, reel_cap)
			&"heft":
				combatant.apply_heft(ability_cost)
			&"reroll":
				combatant.stage_reroll(ability_cost)
			&"hunters_mark":
				combatant.stage_hunters_mark(ability_cost)  # orchestrator attaches the mark to the defender
			&"select_fate":
				combatant.apply_select_fate(selected_fate_type, ability_cost)  # +1 reel, retype loadout (Seer)
			&"rallying_cry":
				combatant.apply_rallying_cry(ability_cost, reel_cap)  # +1 utility reel; orchestrator shields the party
	if fire_ultimate_staged:
		match ultimate_id:
			&"wild":
				combatant.fire_sticky_wild(_weapon_reel_count(), WILD_SPINS)        # single spin (Warrior)
			&"sticky_wild":
				combatant.fire_sticky_wild(_weapon_reel_count(), STICKY_WILD_SPINS)  # two spins (Skirmisher)
			&"rampage":
				combatant.fire_rampage(combatant.weapon_type(), RAMPAGE_CONVERSIONS, RAMPAGE_SPINS)
			&"wildcard_gamble":
				combatant.fire_wildcard_gamble()
			&"collateral":
				combatant.fire_collateral(combatant.weapon_type(), COLLATERAL_SPINS)  # +1 reel; orchestrator splashes
			&"big_bang":
				combatant.fire_big_bang(combatant.weapon_type(), BIG_BANG_REELS, BIG_BANG_SPINS)  # 4 wild AoE reels (Seer)
			&"earthquake":
				combatant.fire_earthquake(combatant.weapon_type(), EARTHQUAKE_SPINS)  # +1 WILD reel; orchestrator splashes + stuns
	# The Big Bang's own type picker (free) retypes the FINAL loadout — including the reels fire_big_bang
	# just appended. Runs after the Ultimate fires. Standalone Select your Fate already retyped in
	# apply_select_fate (and is locked out while Big Bang is staged), so this is the Big Bang path only.
	if selected_fate_type != null and fire_ultimate_staged and ultimate_id == &"big_bang":
		combatant.convert_turn_reels_to(selected_fate_type)
