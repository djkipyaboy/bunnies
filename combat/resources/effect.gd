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

## Whether this effect helps its bearer (buff) vs. harms it (debuff). Drives the UI's buff/debuff
## colour distinction. [ASSUMPTION] data — authored per effect in EffectLibrary.
@export var beneficial: bool = false

## How many times this effect can stack on one bearer (1 = non-stacking). [ASSUMPTION] data.
@export var max_stacks: int = 1

## Per-stack magnitude increments for a stacking effect (e.g. SLOW = [-20, -10, -5] — diminishing).
## When non-empty, effective_magnitude() sums the first [member stacks] entries instead of using
## the flat [member magnitude]. [ASSUMPTION] data.
@export var stack_magnitudes: Array[float] = []

## Live stack count on an attached effect (a freshly made effect is 1 stack). Grown by add_stack().
var stacks: int = 1

## Decrements the remaining duration by one bearer-turn (clamped at 0).
func tick() -> void:
	duration = maxi(duration - 1, 0)

## True once the effect has run out and should be detached.
func is_expired() -> bool:
	return duration <= 0

## The effect's current magnitude given its stack count. For a stacking effect (non-empty
## stack_magnitudes) this is the sum of the first [member stacks] increments; otherwise the flat
## [member magnitude]. Used by Combatant.recompute_initiative for INITIATIVE_MOD effects.
func effective_magnitude() -> float:
	if stack_magnitudes.is_empty():
		return magnitude
	var total: float = 0.0
	var n: int = mini(stacks, stack_magnitudes.size())
	for i: int in range(n):
		total += stack_magnitudes[i]
	return total

## Adds one stack, up to [member max_stacks]. Returns false (no change) when already at the cap or
## for a non-stacking effect (max_stacks == 1).
func add_stack() -> bool:
	if stacks < max_stacks:
		stacks += 1
		return true
	return false
