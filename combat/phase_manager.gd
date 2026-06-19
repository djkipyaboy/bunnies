class_name PhaseManager
extends Node

## Drives one combatant's turn through the MTG-style phases (DESIGN.md §4.8):
## Upkeep → Main 1 → Combat → Main 2 → End.
##
## For the prototype the Main/Upkeep/End phases are pass-through (they emit [signal phase_changed]
## so the UI can show the phase, but spend no resources). The turn PAUSES at Combat so the player
## can spin; the orchestrator calls [method resume_after_combat] once the spin has resolved.

enum Phase { UPKEEP, MAIN_1, COMBAT, MAIN_2, END }

## Emitted on entering each phase, for UI labelling and phase-triggered effects.
signal phase_changed(phase: Phase)

## Emitted after the End phase — the turn is fully over.
signal turn_finished

var current_phase: Phase = Phase.UPKEEP

## Runs Upkeep and Main 1, then stops on Combat awaiting the spin.
func start_turn() -> void:
	_enter(Phase.UPKEEP)
	_enter(Phase.MAIN_1)
	_enter(Phase.COMBAT)

## Resumes after the Combat-phase spin has resolved: runs Main 2 and End, then finishes the turn.
func resume_after_combat() -> void:
	_enter(Phase.MAIN_2)
	_enter(Phase.END)
	turn_finished.emit()

func _enter(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(phase)
