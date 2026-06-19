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

## Max HP — flat pool seeded by class/race, scaling per level (DESIGN.md A1). Not reel-influenced.
var max_hp: int = 1

## The weapon spun in the Combat Phase.
var weapon: Weapon

## The damage type incoming attacks are resolved AGAINST (this combatant's defensive type).
var defense_type: DamageType

## The Bonus Meter (PCs + Elite/Boss only; null for trash enemies).
var bonus_meter: BonusMeter

# ---------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------

var hp: int = 0

## The live turn-order sort key (DESIGN.md §4.1) — DERIVED: base_initiative + active modifiers.
## Set via [method recompute_initiative]; never mutated directly by effects.
var current_initiative: int = 0

## The raw rolled Initiative (TurnManager.roll_initiative). current_initiative builds on this.
var base_initiative: int = 0

## Active buffs/debuffs/riders (DESIGN.md §4.1, A4). Ticked in [method on_end]; own copies (duplicated).
var active_effects: Array[Effect] = []

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

# ---------------------------------------------------------------------------
# Effects & turn-order
# ---------------------------------------------------------------------------

## Recomputes current_initiative as base + the sum of active INITIATIVE_MOD magnitudes (rounded).
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.magnitude
	current_initiative = base_initiative + int(roundf(total))

## Attaches an effect (already a fresh/duplicated instance) and updates the derived sort key.
func attach_effect(effect: Effect) -> void:
	if effect == null:
		return
	# Defensively duplicate so a shared (.tres-loaded) Effect can never share a live duration
	# counter across combatants. Safe even for already-fresh EffectLibrary.make() instances.
	effect = effect.duplicate()
	active_effects.append(effect)
	recompute_initiative()

## Ticks every active effect one bearer-turn, drops the expired ones, and recomputes initiative.
func tick_effects() -> void:
	for e: Effect in active_effects:
		e.tick()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return not e.is_expired())
	recompute_initiative()

# ---------------------------------------------------------------------------
# Per-turn phase hooks (called by the orchestrator off PhaseManager.phase_changed)
# ---------------------------------------------------------------------------

## Start-of-turn bookkeeping: resource regen (Wave B) + refresh the derived sort key.
func on_upkeep() -> void:
	recompute_initiative()

## End-of-turn bookkeeping: tick effect durations (Slow counts down here — DESIGN.md §4.8).
func on_end() -> void:
	tick_effects()
