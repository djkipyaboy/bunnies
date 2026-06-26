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
		c.base_initiative = value + c.effective_stats().finesse
		c.tiebreak_roll = _initiative_tens.spin().digit  # stored d10 final tie-break (a spin, not randf)
		c.recompute_initiative()
		initiative_rolled.emit(c, value)

## Rolls a fresh d100 (percentile, 00=100, range 1–100) from the shared Initiative reels — used by
## the STUNNED "shake off" gate. (DESIGN spec 2026-06-20.)
func roll_d100() -> int:
	return InitiativeReel.roll_percentile(_initiative_tens, _initiative_ones)

## Returns combatants sorted for turn order: current_initiative desc, ties broken by Finesse desc,
## then by the stored d10 tiebreak_roll desc (DESIGN.md §4.1; Finesse stat 2026-06-20).
func get_turn_order() -> Array[Combatant]:
	var ordered: Array[Combatant] = combatants.duplicate()
	ordered.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		if a.current_initiative != b.current_initiative:
			return a.current_initiative > b.current_initiative
		var fa: int = a.effective_stats().finesse
		var fb: int = b.effective_stats().finesse
		if fa != fb:
			return fa > fb
		return a.tiebreak_roll > b.tiebreak_roll)
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
		# Target dummies are excluded: they never die (min_hp 1), so counting them would mean the player
		# could never clear the enemy side and win. They still take turns; they just don't gate combat end.
		if c.is_player == is_player and c.is_alive() and not c.is_target_dummy:
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
