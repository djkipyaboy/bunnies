class_name EffectLibrary
extends RefCounted

## Resolves a rider id (DamageType.inherent_rider_id / ReelFace.rider_effect_id) into a FRESH
## Effect instance. For the prototype this is a small code registry holding the one rider we need —
## Crushing -> Slow. Authorable as .tres later (YAGNI: one rider needs no asset pipeline yet).
##
## Always returns a new Effect (never a shared reference) so each bearer owns its own countdown.

## [ASSUMPTION] placeholder values — tune by playtest (CLAUDE.md §4).
static func make(id: StringName) -> Effect:
	match id:
		&"slow":
			var e: Effect = Effect.new()
			e.id = &"slow"
			e.kind = Effect.Kind.INITIATIVE_MOD
			e.magnitude = -20.0
			e.duration = 2
			return e
		_:
			return null
