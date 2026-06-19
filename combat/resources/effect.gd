class_name Effect
extends Resource

## A buff/debuff/rider applied BY a reel face or weapon type (DESIGN.md §4.1, §4.6; ARCHITECTURE §7).
## Reel faces/types APPLY effects; they don't contain them. The first target rider is Crushing->Slow,
## an INITIATIVE_MOD that lowers the bearer's current_initiative for [member duration] of its turns.
##
## This is a DEFINITION carrying its own live countdown — always attach a duplicate() so two
## combatants never share one duration counter (see EffectLibrary / Combatant.attach_effect).

enum Kind { INITIATIVE_MOD, DAMAGE_OVER_TIME, MULTIPLIER_EDIT, REEL_FACE_EDIT }

## Stable id used by riders to reference this effect (e.g. DamageType.inherent_rider_id = &"slow").
@export var id: StringName = &""

## Which family of effect this is. Only INITIATIVE_MOD is exercised in the prototype.
@export var kind: Kind = Kind.INITIATIVE_MOD

## Signed magnitude (INITIATIVE_MOD: added to current_initiative — negative = Slow). [ASSUMPTION] data.
@export var magnitude: float = 0.0

## Remaining turns on the bearer. Ticks down in Combatant.on_end(); removed when it hits 0.
@export var duration: int = 1

## Decrements the remaining duration by one bearer-turn (clamped at 0).
func tick() -> void:
	duration = maxi(duration - 1, 0)

## True once the effect has run out and should be detached.
func is_expired() -> bool:
	return duration <= 0
