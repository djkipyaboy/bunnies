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

# ---------------------------------------------------------------------------
# Identity & configuration
# ---------------------------------------------------------------------------

var display_name: String = ""
var is_player: bool = false

## The class's Main-1 base ability id (spec 2026-06-21 §4A): &"rend" / &"heft" / &"flurry".
## Drives MainPhasePlan dispatch. Empty = no base ability.
var ability_id: StringName = &""

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
var base_meter_floor: int = 0

# ---------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------

var hp: int = 0

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

## STUNNED is a per-turn condition (NOT a duration Effect): set at turn start when current_initiative
## is below the threshold and the combatant wasn't STUNNED last turn (anti-lock). DESIGN spec 2026-06-20.
var stunned_this_turn: bool = false
var stunned_last_turn: bool = false

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Initializes live state at the start of a combat: full HP.
func start_combat() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)

## Applies [param amount] damage, clamped so HP never goes negative. Emits [signal hp_changed],
## and [signal defeated] once when HP reaches 0. No-op if already dead or amount ≤ 0.
func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		defeated.emit()

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
		resource_pool.max_stamina = base_max_stamina + s.focus
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
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

## Ticks every active effect one bearer-turn, drops the expired ones, and recomputes initiative.
func tick_effects() -> void:
	for e: Effect in active_effects:
		e.tick()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return not e.is_expired())
	recompute_initiative()

# ---------------------------------------------------------------------------
# Per-turn reel loadout (Main-Phase editing — DESIGN.md §4.8)
# ---------------------------------------------------------------------------

## Resets this turn's reel set to the weapon baseline. Call at the start of the turn (Upkeep/Main 1).
func begin_turn() -> void:
	turn_reels = weapon.reels.duplicate() if weapon != null else []

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

## Vanguard "Heft" (spec §4A): spends [param cost] Stamina and, on each reel of THIS turn, converts
## its first FAILURE face into a SUCCESS face (mult 1.0) — fewer whiffs from the heavy hits. Edits a
## DEEP copy of each reel so the underlying weapon is never mutated (begin_turn's duplicate is shallow,
## so the ActionReel/ReelFace objects are shared with the weapon). Returns false (no change) if
## unaffordable.
func apply_heft(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	for i: int in range(turn_reels.size()):
		var reel: ActionReel = turn_reels[i].duplicate(true)  # deep: its own faces
		for face: ReelFace in reel.faces:
			if face.result_tier == ReelFace.ResultTier.FAILURE:
				face.result_tier = ReelFace.ResultTier.SUCCESS
				face.multiplier = 1.0
				break
		turn_reels[i] = reel
	return true

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
	stunned_last_turn = stunned_this_turn
	stunned_this_turn = false

## Recomputes STUNNED for this turn: stunned when current_initiative < [param threshold] AND not
## immune (immune = STUNNED last turn — the anti-lock that prevents a permanent lockout). Returns
## the new stunned_this_turn. Call at turn start, after on_upkeep has recomputed initiative.
func evaluate_stun(threshold: int) -> bool:
	stunned_this_turn = current_initiative < threshold and not stunned_last_turn
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
