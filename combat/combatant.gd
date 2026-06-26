class_name Combatant
extends RefCounted

## A combatant in a fight — PC or enemy (DESIGN.md §8). Holds live combat state; built for
## N-vs-M though the prototype runs 1v1. Pure logic + signals, no scene presence (the UI binds
## to its signals).

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever [member hp] changes, for HP-bar binding.
signal hp_changed(hp: int, max_hp: int)

## Emitted once when this combatant drops to 0 HP.
signal defeated

## Emitted whenever shield_hp or shield_turns changes, for shield-chip UI binding.
signal shield_changed(shield_hp: int, shield_turns: int)

# ---------------------------------------------------------------------------
# Identity & configuration
# ---------------------------------------------------------------------------

var display_name: String = ""
var is_player: bool = false

## A non-combat TARGET DUMMY (debug/testing aid): takes splash/AoE damage so the player can see it land,
## never dies (see [member min_hp]), spends its turn healing to full, and is EXCLUDED from the combat-end
## check (TurnManager._living) so immortal dummies can't stall a win. Not used in normal play.
var is_target_dummy: bool = false

## The class's Main-1 base ability id (spec 2026-06-21 §4A): &"rend" / &"heft" / &"flurry".
## Drives MainPhasePlan dispatch. Empty = no base ability.
var ability_id: StringName = &""

## Cost + rail of the Main-1 base ability (set from CharacterClass). Drives MainPhasePlan.
var ability_cost: int = 2
var ability_resource: StringName = &"stamina"

## The class's Ultimate archetype id. &"sticky_wild" (Warrior/Skirmisher placeholder) or &"rampage"
## (Vanguard: +1 reel, Heft-all, AoE). Drives MainPhasePlan's ultimate dispatch.
var ultimate_id: StringName = &"sticky_wild"

## Payline profile (spec 2026-06-23): &"default" or &"casino" (Chancer). Drives orchestrator scoring.
var payline_profile_id: StringName = &"default"

## Max HP — flat pool seeded by class/race, scaling per level (DESIGN.md A1). Not reel-influenced.
var max_hp: int = 1

## The weapon spun in the Combat Phase.
var weapon: Weapon

## The damage type incoming attacks are resolved AGAINST (this combatant's defensive type).
var defense_type: DamageType

## The Bonus Meter (PCs + Elite/Boss only; null for trash enemies).
var bonus_meter: BonusMeter

## Stamina/Focus/Mana spent in Main 1 (DESIGN.md §10 Dec 6). Null = no resource economy.
var resource_pool: ResourcePool

## Base (innate) stats from race/class. Gear adds on top — see [method effective_stats].
var base_stats: Stats

## Equipped items contributing stat bonuses (DESIGN.md A7).
var gear: Array[Gear] = []

## Pre-stat seeds; the live max_hp / pool max / meter floor are DERIVED in [method apply_stats].
var base_max_hp: int = 1
var base_max_stamina: int = 0
var base_max_mana: int = 0
var base_meter_floor: int = 0

# ---------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------

var hp: int = 0

## Floor HP can be reduced to by [method take_damage] (default 0 = can die). Target dummies set this to
## 1 so they survive any hit (retain 1 HP) — a testing aid, not a normal combat mechanic.
var min_hp: int = 0

## The live turn-order sort key (DESIGN.md §4.1) — DERIVED: base_initiative + active modifiers.
## Set via [method recompute_initiative]; never mutated directly by effects.
var current_initiative: int = 0

## The raw rolled Initiative (TurnManager.roll_initiative). current_initiative builds on this.
var base_initiative: int = 0

## Final initiative tie-break — a stored d10 reel roll set in TurnManager.roll_initiative.
var tiebreak_roll: int = 0

## Active buffs/debuffs/riders (DESIGN.md §4.1, A4). Ticked in [method on_end]; own copies (duplicated).
var active_effects: Array[Effect] = []

## The reels actually spun this Combat Phase: a per-turn copy of weapon.reels that Main-1 actions
## edit ADDITIVELY (DESIGN.md §8 "resolved set of reels"). Reset each turn by [method begin_turn].
var turn_reels: Array[ActionReel] = []

## Sticky-Wild Ultimate state (DESIGN.md §4.9). sticky_wild_count = how many LEADING reels are
## forced to crit-success (the weapon reels — splices are excluded by passing only the weapon count
## at fire time); 0 = none. sticky_wild_spins_remaining counts the spins the wild still applies for.
var sticky_wild_count: int = 0
var sticky_wild_spins_remaining: int = 0

## Vanguard "Rampage" Ultimate state (spec §4A): while > 0, this combatant's attacks this spin are
## Area-of-Effect (hit ALL enemies). Set by [method fire_rampage], consumed by [method consume_aoe_spin].
var aoe_spins_remaining: int = 0

## Ranger "Collateral Damage" Ultimate state (spec §3.4): while > 0, this combatant added a reel and
## its spin splashes half its primary total to every OTHER enemy as Piercing. SEPARATE from
## aoe_spins_remaining because the primary takes FULL damage (not half) and stays mark-eligible — only
## the splash is the AoE portion. Set by [method fire_collateral], consumed by [method consume_collateral_spin].
var collateral_spins_remaining: int = 0

## Ranger "Hunter's Mark" base ability (spec §3.4): staged in Main 1, this flags that the orchestrator
## should attach the &"hunters_mark" debuff to the current defender at commit. Stamina is spent here;
## the orchestrator (which knows the enemy target) does the attach + clears the flag.
var hunters_mark_pending: bool = false

## Chancer post-spin state (spec §3.1). reroll_pending: the base Re-roll ability re-rolls the single
## worst reel after the spin (refunding reroll_cost if nothing qualified). wildcard_gamble_pending: the
## Ultimate re-rolls every non-crit reel (double-or-nothing). Both are consumed/cleared post-spin.
var reroll_pending: bool = false
var reroll_cost: int = 0
var wildcard_gamble_pending: bool = false

## Seer "The Big Bang" Ultimate state (spec 2026-06-27 §4): while > 0, this combatant topped its loadout
## to 4 crit-biased WILD reels and the spin is AoE; the orchestrator then heals all allies ceil(total/6),
## overflow → SHIELDED. Tracked separately from aoe/wild (which it sets) so the post-spin heal fires once.
var big_bang_spins_remaining: int = 0

## STUNNED is a per-turn condition (NOT a duration Effect): set at turn start when current_initiative
## is below the threshold and the combatant wasn't STUNNED last turn (anti-lock). DESIGN spec 2026-06-20.
var stunned_this_turn: bool = false
var stunned_last_turn: bool = false

## Earthquake (Warden Ultimate, spec 2026-06-29 §4.3) force-stun: a one-shot flag set by the
## orchestrator on every enemy the Earthquake damaged. evaluate_stun honors it to STUN the bearer next
## turn REGARDLESS of initiative and WITHOUT changing current_initiative (queue position preserved),
## bypassing the anti-lock so the expensive Ultimate reliably lands. Consumed when evaluated.
var force_stun_next_turn: bool = false

## SHIELDED buff (spec 2026-06-22 §1.2): a damage-absorbing pool. take_damage spends shield_hp before
## HP; shield_turns counts down in on_end. Higher-total-overrides on re-apply (apply_shield). Combatant
## STATE (not an Effect) because the absorb math lives in take_damage.
var shield_hp: int = 0
var shield_turns: int = 0

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Initializes live state at the start of a combat: full HP.
func start_combat() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)

## Applies [param amount] damage. SHIELDED absorbs first (and the shield clears if fully spent), then
## the remainder hits HP, clamped so HP never goes negative. Emits [signal hp_changed], and
## [signal defeated] once when HP reaches 0. No-op if already dead or amount ≤ 0.
func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	var remaining: int = amount
	if shield_hp > 0:
		var absorbed: int = mini(shield_hp, remaining)
		shield_hp -= absorbed
		remaining -= absorbed
		if shield_hp == 0:
			shield_turns = 0
		shield_changed.emit(shield_hp, shield_turns)
	if remaining <= 0:
		return
	hp = maxi(hp - remaining, min_hp)  # min_hp > 0 (target dummies) survive any hit, retaining min_hp
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		defeated.emit()

## Applies a SHIELDED buff of [param amount] HP for [param turns] turns. Higher-total-overrides
## (spec §1.2 / §3.3): replaces the current shield only if [param amount] exceeds it; otherwise no-op.
func apply_shield(amount: int, turns: int) -> void:
	if amount <= 0 or amount <= shield_hp:
		return
	shield_hp = amount
	shield_turns = turns
	shield_changed.emit(shield_hp, shield_turns)

## Restores [param amount] HP, clamped to max_hp. Returns the OVERFLOW (amount that exceeded max) so a
## caller (e.g. Big Bang) can convert it to a shield. No-op (returns 0) if dead or amount ≤ 0.
func heal(amount: int) -> int:
	if amount <= 0 or hp <= 0:
		return 0
	var before: int = hp
	hp = mini(hp + amount, max_hp)
	if hp != before:
		hp_changed.emit(hp, max_hp)
	return amount - (hp - before)

## True while this combatant still has HP.
func is_alive() -> bool:
	return hp > 0

## Effective stats = base_stats + every equipped gear's stat_bonuses (null-safe → zeroes).
func effective_stats() -> Stats:
	var s: Stats = Stats.new()
	if base_stats != null:
		s = s.plus(base_stats)
	for g: Gear in gear:
		if g != null:
			s = s.plus(g.stat_bonuses)
	return s

## Recomputes the stat-derived values (max HP / pool max / meter floor). Call at setup AFTER gear is
## equipped and BEFORE start_combat(). [ASSUMPTION] flat 1:1 mappings.
func apply_stats() -> void:
	var s: Stats = effective_stats()
	max_hp = base_max_hp + s.vigor
	if resource_pool != null:
		# Focus boosts only the rail(s) the class actually USES (base > 0): a stamina class gets no phantom
		# mana pool, and a mana-only caster (Seer, base_max_stamina = 0) gets no phantom stamina rail.
		resource_pool.max_stamina = (base_max_stamina + s.focus) if base_max_stamina > 0 else 0
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
		resource_pool.max_mana = (base_max_mana + s.focus) if base_max_mana > 0 else 0
		resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
	if bonus_meter != null:
		bonus_meter.floor = base_meter_floor + s.grit

## Edits this combatant's weapon reels to add crit-success faces equal to its Luck (the reel IS the
## dice — Luck raises crit ODDS via more crit FACES, then reshuffles to distribute them). Mutates this
## combatant's OWN weapon reels only (N-vs-M safe — each combatant has its own Weapon). Call ONCE at
## setup (after gear/apply_stats); NOT idempotent — each call appends more faces, so do not re-apply.
## [ASSUMPTION] +1 crit-success face (×2.0) per point of Luck.
func apply_luck() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().luck
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		for i: int in range(n):
			var f: ReelFace = ReelFace.new()
			f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			f.multiplier = 2.0
			reel.faces.append(f)
		reel.faces.shuffle()

# ---------------------------------------------------------------------------
# Effects & turn-order
# ---------------------------------------------------------------------------

## Recomputes current_initiative as base + the sum of active INITIATIVE_MOD magnitudes (rounded).
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.effective_magnitude()
	current_initiative = base_initiative + int(roundf(total))

## Attaches an effect (already a fresh/duplicated instance) and updates the derived sort key.
func attach_effect(effect: Effect) -> void:
	if effect == null:
		return
	# Merge by id: re-applying an effect already active never creates a second instance (this is
	# what prevents unbounded additive stacking). A stacking effect adds a stack (diminishing,
	# capped); a non-stacking one is a no-op on stacks. Either way the duration is refreshed.
	var existing: Effect = _find_effect(effect.id)
	if existing != null:
		existing.add_stack()                 # no-op at cap / for max_stacks == 1
		existing.duration = effect.duration   # refresh to the incoming duration
		recompute_initiative()
		return
	# New id: defensively duplicate so a shared (.tres-loaded) Effect can't share a live counter
	# across combatants (safe even for fresh EffectLibrary.make() instances), then append.
	effect = effect.duplicate()
	active_effects.append(effect)
	recompute_initiative()

## Returns the active effect with [param id], or null if none is active.
func _find_effect(id: StringName) -> Effect:
	for e: Effect in active_effects:
		if e != null and e.id == id:
			return e
	return null

## True if an effect with [param id] is currently active on this combatant. Used by the orchestrator
## to test the Ranger's Hunter's Mark on a defender before applying the crit-fail→hit reel swap.
func has_effect(id: StringName) -> bool:
	return _find_effect(id) != null

## Ticks every active effect one bearer-turn, drops the expired ones, and recomputes initiative.
func tick_effects() -> void:
	for e: Effect in active_effects:
		e.tick()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return not e.is_expired())
	recompute_initiative()

## Removes all non-beneficial (debuff) effects, keeping buffs, then refreshes the derived sort key.
## Returns the number of effects removed. Used by the Warden Pick'em Ultimate (spec §3.3).
func cleanse() -> int:
	var before: int = active_effects.size()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return e != null and e.beneficial)
	recompute_initiative()
	return before - active_effects.size()

# ---------------------------------------------------------------------------
# Per-turn reel loadout (Main-Phase editing — DESIGN.md §4.8)
# ---------------------------------------------------------------------------

## Resets this turn's reel set to the weapon baseline. Call at the start of the turn (Upkeep/Main 1).
## A weaponless combatant (e.g. a target dummy) gets an empty loadout — clear() keeps the array's type.
func begin_turn() -> void:
	if weapon != null:
		turn_reels = weapon.reels.duplicate()
	else:
		turn_reels.clear()

## Splices one extra [param type]-typed reel onto THIS turn (additive, never overwrites the weapon).
## Spends [param cost] Stamina and respects the [param cap]-reel band ceiling. Returns false (and
## changes nothing) if unaffordable or already at the cap (DESIGN.md §4.3, §4.8).
func try_splice_reel(type: DamageType, base_damage: float, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_default(type))
	return true

## Splices one [param type]-typed REND reel onto THIS turn (the Warrior's Rend ability). Same as
## [method try_splice_reel] but the added reel deals no direct damage and applies BLEED on a hit
## (see [method ActionReel.make_rend]).
func try_rend_reel(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rend(type))
	return true

## The weapon's own damage type (its first reel's type), or null. Used by Flurry/Rend to splice an
## own-type extra reel.
func weapon_type() -> DamageType:
	if weapon != null and not weapon.reels.is_empty():
		return weapon.reels[0].damage_type
	return null

## Seer "Select your Fate!" base ability (spec 2026-06-27 §3): spends [param cost] Mana, appends one extra
## [param chosen_type] weapon-attack reel onto THIS turn (2 → 3, so it JOINS the payline grid — unlike the
## Flurry/Rend splices), and retypes the WHOLE turn loadout to [param chosen_type]. Returns false (no change)
## if unaffordable. The orchestrator picks the type via a 6-button modal before committing.
func apply_select_fate(chosen_type: DamageType, cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	turn_reels.append(ActionReel.make_default(chosen_type))  # +1 weapon-attack reel (joins paylines)
	convert_turn_reels_to(chosen_type)
	return true

## Retypes every reel of THIS turn to [param type]. Deep-copies each reel first (begin_turn's duplicate is
## shallow → the reels are shared with the weapon), so the conversion never mutates the underlying weapon.
## Shared by Select your Fate and its Big-Bang combo (which retypes Big Bang's appended reels too).
func convert_turn_reels_to(type: DamageType) -> void:
	for i: int in range(turn_reels.size()):
		var r: ActionReel = turn_reels[i].duplicate(true)  # deep: its own faces
		r.damage_type = type
		turn_reels[i] = r

## Index of the single worst reel to re-roll (Chancer): priority CRIT_FAILURE > FAILURE > NEUTRAL,
## first occurrence on a tie. Returns -1 when no reel landed any of those tiers (nothing to re-roll).
## Static + pure (operates on an Array of CombatResolver.AttackResult) so it is trivially testable.
static func worst_reroll_index(attacks: Array) -> int:
	var priority: Array = [ReelFace.ResultTier.CRIT_FAILURE, ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.NEUTRAL]
	for tier in priority:
		for i: int in range(attacks.size()):
			var a = attacks[i]
			if a != null and a.face != null and a.face.result_tier == tier:
				return i
	return -1

## Hunter's Mark (Ranger ability, spec §3.4) reel transform: returns a copy of [param reels] in which
## every WEAPON-ATTACK reel has its CRIT_FAILURE faces converted to SUCCESS (×1.0) — the accuracy
## debuff that turns an attacker's fumbles into hits while the target is marked. Weapon-attack reels are
## DEEP-copied (their faces are edited on the copy; the originals/weapon are never mutated, matching the
## Heft pattern); utility reels (is_weapon_attack == false, e.g. Rend) pass through untouched. Static +
## pure so the N-vs-M face-swap is unit-testable; the orchestrator applies it pre-resolution when the
## defender is marked and the attacker is not strictly-AoE.
static func hunters_mark_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			var copy: ActionReel = r.duplicate(true)  # deep: its own faces
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
					f.result_tier = ReelFace.ResultTier.SUCCESS
					f.multiplier = 1.0
			out.append(copy)
		else:
			out.append(r)
	return out

## Wildcard Gamble (Chancer Ultimate) double-or-nothing transform for ONE re-rolled reel: a crit-success
## re-roll doubles the reel's original damage; a fail/crit-fail re-roll zeroes it; anything else leaves
## the original standing. Static + pure.
static func gamble_final_damage(rerolled_tier: int, original_final_damage: int) -> int:
	if rerolled_tier == ReelFace.ResultTier.CRIT_SUCCESS:
		return original_final_damage * 2
	if rerolled_tier == ReelFace.ResultTier.FAILURE or rerolled_tier == ReelFace.ResultTier.CRIT_FAILURE:
		return 0
	return original_final_damage

## Vanguard "Heft" (spec §4A): spends [param cost] Stamina and, on each reel of THIS turn, converts
## its first FAILURE face into a SUCCESS face (mult 1.0) — fewer whiffs from the heavy hits. Edits a
## DEEP copy of each reel so the underlying weapon is never mutated (begin_turn's duplicate is shallow,
## so the ActionReel/ReelFace objects are shared with the weapon). Returns false (no change) if
## unaffordable.
func apply_heft(cost: int, conversions: int = 3) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	_heft_turn_reels(conversions)
	return true

## Converts up to [param conversions] "miss" faces (FAILURE first, then CRIT_FAILURE) into SUCCESS
## faces on each of THIS turn's reels. Edits a DEEP copy of each reel so the weapon is never mutated
## (begin_turn's duplicate is shallow). Shared by Heft and the Vanguard Ultimate; no Stamina cost.
func _heft_turn_reels(conversions: int) -> void:
	for i: int in range(turn_reels.size()):
		var reel: ActionReel = turn_reels[i].duplicate(true)  # deep: its own faces
		var done: int = 0
		for tier: ReelFace.ResultTier in [ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.CRIT_FAILURE]:
			if done >= conversions:
				break
			for face: ReelFace in reel.faces:
				if done >= conversions:
					break
				if face.result_tier == tier:
					face.result_tier = ReelFace.ResultTier.SUCCESS
					face.multiplier = 1.0
					done += 1
		turn_reels[i] = reel

# ---------------------------------------------------------------------------
# Per-turn phase hooks (called by the orchestrator off PhaseManager.phase_changed)
# ---------------------------------------------------------------------------

## Start-of-turn bookkeeping: resource regen (Wave B) + refresh the derived sort key.
func on_upkeep() -> void:
	if resource_pool != null:
		resource_pool.regen()
	recompute_initiative()

## End-of-turn bookkeeping: tick effect durations (Slow counts down here — DESIGN.md §4.8), then
## carry the STUNNED flag forward for the anti-lock (this turn's stun becomes last turn's immunity).
func on_end() -> void:
	tick_effects()
	if shield_turns > 0:
		shield_turns -= 1
		if shield_turns == 0:
			shield_hp = 0
		shield_changed.emit(shield_hp, shield_turns)
	stunned_last_turn = stunned_this_turn
	stunned_this_turn = false

## Recomputes STUNNED for this turn: stunned when current_initiative < [param threshold] AND not
## immune (immune = STUNNED last turn — the anti-lock that prevents a permanent lockout). Returns
## the new stunned_this_turn. Call at turn start, after on_upkeep has recomputed initiative.
func evaluate_stun(threshold: int) -> bool:
	var forced: bool = force_stun_next_turn
	force_stun_next_turn = false  # one-shot: consume on evaluation
	# Forced (Earthquake) stun bypasses the anti-lock; init-based stun still respects it (the spiral case).
	var by_initiative: bool = current_initiative < threshold and not stunned_last_turn
	stunned_this_turn = forced or by_initiative
	return stunned_this_turn

## The d100 "shake off" gate: a roll of 51+ recovers (takes the turn); 01–50 loses the turn.
static func stun_check_passed(roll: int) -> bool:
	return roll >= 51

# ---------------------------------------------------------------------------
# Sticky-Wild Ultimate (DESIGN.md §4.9) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Sticky-Wild Ultimate if the meter is armed: consumes the full meter and forces the
## first [param reel_count] reels to land crit-success for the next [param spins] spins. Pass the
## WEAPON reel count so spliced/ability reels stay normal. Returns false if not armed.
func fire_sticky_wild(reel_count: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	sticky_wild_count = reel_count
	sticky_wild_spins_remaining = spins
	return true

## The reels currently forced to crit-success (for the resolver): [0, 1, …, sticky_wild_count-1]
## while a wild is active. Empty when no wild is active.
func wild_reel_indices() -> Array[int]:
	var out: Array[int] = []
	if sticky_wild_spins_remaining > 0 and sticky_wild_count > 0:
		for i: int in range(sticky_wild_count):
			out.append(i)
	return out

## Consumes one sticky-wild spin; clears the wild when exhausted. Call once per resolved spin.
func consume_wild_spin() -> void:
	if sticky_wild_spins_remaining > 0:
		sticky_wild_spins_remaining -= 1
		if sticky_wild_spins_remaining == 0:
			sticky_wild_count = 0

# ---------------------------------------------------------------------------
# Vanguard "Rampage" Ultimate (spec §4A) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Rampage Ultimate if the meter is armed: consumes the full meter, splices one extra
## [param extra_reel_type] reel onto this turn (e.g. 2 → 3), applies the Heft bonus ([param
## conversions] miss→hit per reel) to ALL of this turn's reels, and marks the next [param spins]
## spins as Area-of-Effect (attacks hit ALL enemies). Returns false if not armed.
func fire_rampage(extra_reel_type: DamageType, conversions: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	turn_reels.append(ActionReel.make_default(extra_reel_type))  # +1 attack reel for the Rampage turn
	_heft_turn_reels(conversions)                                # Heft bonus on every reel (incl. the new one)
	aoe_spins_remaining = spins
	return true

## True while a Rampage AoE spin is pending (this combatant's attacks hit all enemies).
func is_aoe_active() -> bool:
	return aoe_spins_remaining > 0

## Consumes one Rampage AoE spin. Call once per resolved spin.
func consume_aoe_spin() -> void:
	if aoe_spins_remaining > 0:
		aoe_spins_remaining -= 1

# ---------------------------------------------------------------------------
# Ranger "Collateral Damage" Ultimate (spec §3.4) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Collateral Damage Ultimate if the meter is armed: consumes the full meter, splices one
## extra [param extra_reel_type] weapon-attack reel onto this turn (e.g. 4 → 5), and flags the next
## [param spins] spins as Collateral. The primary defender takes FULL weapon damage (normal resolution);
## the orchestrator then splashes half the primary total to every OTHER enemy as Piercing. NOT an AoE
## spin (is_aoe_active stays false) so the primary hit remains Hunter's-Mark-eligible. Returns false if
## not armed.
func fire_collateral(extra_reel_type: DamageType, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	turn_reels.append(ActionReel.make_default(extra_reel_type))  # +1 weapon-attack reel for the Collateral turn
	collateral_spins_remaining = spins
	return true

## True while a Collateral splash spin is pending (this combatant's spin splashes to other enemies).
func is_collateral_active() -> bool:
	return collateral_spins_remaining > 0

## Consumes one Collateral spin. Call once per resolved spin.
func consume_collateral_spin() -> void:
	if collateral_spins_remaining > 0:
		collateral_spins_remaining -= 1

# ---------------------------------------------------------------------------
# Seer "The Big Bang" Ultimate (spec 2026-06-27 §4) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Big Bang Ultimate if the meter is armed: consumes the full meter, tops this turn's loadout up to
## [param target_reels] weapon-attack reels (the Seer's 2 → 4 by appending [param extra_reel_type] reels),
## makes ALL of them crit-biased WILD and the spin AoE for [param spins] spins (reusing the wild + AoE paths),
## and flags the post-spin party heal. The orchestrator then heals each ally ceil(total/6), overflow → a
## 2-turn SHIELDED. Returns false if not armed.
func fire_big_bang(extra_reel_type: DamageType, target_reels: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	while turn_reels.size() < target_reels:
		turn_reels.append(ActionReel.make_default(extra_reel_type))  # top up to the Big Bang reel count
	sticky_wild_count = turn_reels.size()      # every reel crit-biased (reuse the wild path)
	sticky_wild_spins_remaining = spins
	aoe_spins_remaining = spins                 # hits ALL enemies (reuse the AoE path)
	big_bang_spins_remaining = spins
	return true

## True while a Big Bang spin is pending (drives the orchestrator's post-spin party heal/shield).
func is_big_bang_active() -> bool:
	return big_bang_spins_remaining > 0

## Consumes one Big Bang spin. Call once per resolved spin (after the heal has been applied).
func consume_big_bang_spin() -> void:
	if big_bang_spins_remaining > 0:
		big_bang_spins_remaining -= 1

# ---------------------------------------------------------------------------
# Ranger "Hunter's Mark" base ability (spec §3.4) — costs Stamina; applied by the orchestrator
# ---------------------------------------------------------------------------

## Stages Hunter's Mark: spends [param cost] Stamina and flags a pending mark. The orchestrator (which
## knows the enemy target) attaches the &"hunters_mark" debuff to the defender at commit and clears the
## flag. Returns false (no change) if unaffordable.
func stage_hunters_mark(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	hunters_mark_pending = true
	return true

# ---------------------------------------------------------------------------
# Chancer reroll / Wildcard Gamble (spec §3.1) — reroll costs Stamina; gamble costs the meter
# ---------------------------------------------------------------------------

## Stages the Re-roll base ability: spends [param cost] Stamina and flags a post-spin re-roll of the
## worst reel. Returns false (no change) if unaffordable. The orchestrator runs the re-roll after the
## spin resolves, and calls refund_reroll() if no reel qualified.
func stage_reroll(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	reroll_pending = true
	reroll_cost = cost
	return true

## Refunds a staged Re-roll's Stamina (no reel qualified) and clears its state.
func refund_reroll() -> void:
	if reroll_cost > 0 and resource_pool != null:
		resource_pool.refund({&"stamina": reroll_cost})
	reroll_pending = false
	reroll_cost = 0

## Fires the Wildcard Gamble Ultimate if the meter is armed: consumes the full meter and flags the
## post-spin double-or-nothing re-roll of every non-crit reel. Returns false if not armed.
func fire_wildcard_gamble() -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	wildcard_gamble_pending = true
	return true

## Clears post-spin reroll/gamble flags (no refund). Call after the orchestrator has applied them.
func clear_reroll_state() -> void:
	reroll_pending = false
	reroll_cost = 0
	wildcard_gamble_pending = false
