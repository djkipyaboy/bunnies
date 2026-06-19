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

## The live turn-order sort key (DESIGN.md §4.1). Effects modify this with a duration.
var current_initiative: int = 0

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
