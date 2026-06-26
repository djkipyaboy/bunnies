class_name EffectLibrary
extends RefCounted

## Resolves a rider id (DamageType.inherent_rider_id / ReelFace.rider_effect_id) into a FRESH
## Effect instance. For the prototype this is a small code registry holding the riders we need —
## Crushing -> Slow, the Inspirational party buff, and the Warrior's Rend -> Bleed DoT.
## Authorable as .tres later (YAGNI: a few riders need no asset pipeline yet).
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
		&"bleed":
			# Warrior's Rend rider (spec §4B): 3-turn DoT, stacks 3x at 50/80/115% of the caster's
			# weapon base damage per turn. dot_base_damage is baked by the orchestrator at apply
			# time (the Warrior's equipped weapon base). Off the type chart; rounds up.
			var e: Effect = Effect.new()
			e.id = &"bleed"
			e.kind = Effect.Kind.DAMAGE_OVER_TIME
			e.duration = 3
			e.max_stacks = 3
			e.dot_fractions = [0.50, 0.80, 1.15]
			e.beneficial = false
			return e
		&"hunters_mark":
			# Ranger's Hunter's Mark (spec §3.4): a 3-turn accuracy debuff on ONE enemy. It carries no
			# initiative/DoT payload — it's a MARKER. While the bearer is marked, any non-AoE attacker's
			# weapon-attack reels have their crit-fail face swapped for a HIT (applied by the orchestrator
			# via Combatant.hunters_mark_reels). Kind REEL_FACE_EDIT is inert in recompute_initiative and
			# _apply_dot, so the effect only exists to be detected by has_effect + ticked over 3 turns.
			var e: Effect = Effect.new()
			e.id = &"hunters_mark"
			e.kind = Effect.Kind.REEL_FACE_EDIT
			e.duration = 3
			e.max_stacks = 1
			e.beneficial = false
			return e
		_:
			return null
