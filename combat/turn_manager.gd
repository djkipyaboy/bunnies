class_name TurnManager
extends Node

## Runs combat as fixed-order rounds in descending current-Initiative (DESIGN.md §4.1).
## Built for N-vs-M; the prototype uses 1v1. Turn advancement is synchronous and driven by the
## orchestrator (combat.gd calls [method advance_turn] once a turn's spin has fully resolved), so
## animation timing lives in the scene, not here.

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal initiative_rolled(combatant: Combatant, value: int)
signal round_started(round_number: int)
signal turn_started(combatant: Combatant)
signal combat_ended(winner_is_player: bool)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

## All combatants in the fight (any mix of players/enemies).
var combatants: Array[Combatant] = []

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var round_number: int = 0

## The two shared d10 digit reels for the Initiative percentile spin (DESIGN.md §4.2).
var _initiative_tens: InitiativeReel = InitiativeReel.make_default()
var _initiative_ones: InitiativeReel = InitiativeReel.make_default()

var _order: Array[Combatant] = []
var _turn_index: int = 0

# ---------------------------------------------------------------------------
# Initiative & ordering
# ---------------------------------------------------------------------------

## Rolls Initiative once for every combatant (2-reel d100, 00=100) and stores it as the live
## sort key. Emits [signal initiative_rolled] per combatant (DESIGN.md §4.1–§4.2).
func roll_initiative() -> void:
	for c: Combatant in combatants:
		var value: int = InitiativeReel.roll_percentile(_initiative_tens, _initiative_ones)
		c.current_initiative = value
		initiative_rolled.emit(c, value)

## Returns combatants sorted by current_initiative, descending (the turn order).
func get_turn_order() -> Array[Combatant]:
	var ordered: Array[Combatant] = combatants.duplicate()
	ordered.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		return a.current_initiative > b.current_initiative)
	return ordered

# ---------------------------------------------------------------------------
# Combat-end queries
# ---------------------------------------------------------------------------

## Combat ends when one side has no living members left (DESIGN.md §4.7).
func is_combat_over() -> bool:
	return _living(true).is_empty() or _living(false).is_empty()

## True when at least one player is still standing (meaningful once combat is over).
func winner_is_player() -> bool:
	return not _living(true).is_empty()

func _living(is_player: bool) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in combatants:
		if c.is_player == is_player and c.is_alive():
			out.append(c)
	return out

# ---------------------------------------------------------------------------
# Turn advancement (driven by the orchestrator)
# ---------------------------------------------------------------------------

## Starts combat: opens round 1 and announces the first actor. Initiative should already be rolled.
func begin() -> void:
	round_number = 0
	_start_next_round()

## Advances to the next living actor; rolls into a new round when the current one is exhausted,
## or emits [signal combat_ended] if one side has fallen.
func advance_turn() -> void:
	if is_combat_over():
		combat_ended.emit(winner_is_player())
		return
	_turn_index += 1
	_announce_current()

func _start_next_round() -> void:
	if is_combat_over():
		combat_ended.emit(winner_is_player())
		return
	round_number += 1
	_order = get_turn_order()
	_turn_index = 0
	round_started.emit(round_number)
	_announce_current()

## Skips fallen combatants at the cursor; rolls into a new round past the end; else announces the
## actor whose turn it is.
func _announce_current() -> void:
	while _turn_index < _order.size() and not _order[_turn_index].is_alive():
		_turn_index += 1
	if _turn_index >= _order.size():
		_start_next_round()
		return
	turn_started.emit(_order[_turn_index])
