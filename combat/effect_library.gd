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
			e.max_stacks = 3
			e.stack_magnitudes = [-20.0, -10.0, -5.0]
			e.beneficial = false
			return e
		&"inspirational":
			var e: Effect = Effect.new()
			e.id = &"inspirational"
			e.kind = Effect.Kind.INITIATIVE_MOD
			e.magnitude = 5.0
			e.duration = 2
			e.max_stacks = 1
			e.beneficial = true
			return e
		_:
			return null
