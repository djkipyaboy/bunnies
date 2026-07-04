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
		&"sundered":
			var e: Effect = Effect.new()
			e.id = &"sundered"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 1.25
			e.affects_incoming = true; e.duration = 2; e.beneficial = false
			return e
		&"weakened":
			var e: Effect = Effect.new()
			e.id = &"weakened"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.75
			e.affects_incoming = false; e.duration = 2; e.beneficial = false
			return e
		&"jinxed":
			# Downgrades the BEARER's own success/crit-success faces (applied by the attacker's-turn
			# orchestrator check, mirroring Hunter's Mark's REEL_FACE_EDIT precedent — no numeric payload).
			var e: Effect = Effect.new()
			e.id = &"jinxed"; e.kind = Effect.Kind.REEL_FACE_EDIT; e.duration = 2; e.beneficial = false
			return e
		&"rooted":
			var e: Effect = Effect.new()
			e.id = &"rooted"; e.kind = Effect.Kind.INITIATIVE_MOD; e.magnitude = -30.0
			e.duration = 2; e.max_stacks = 1; e.beneficial = false
			return e
		&"guarded":
			var e: Effect = Effect.new()
			e.id = &"guarded"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 0.75
			e.affects_incoming = true; e.duration = 2; e.beneficial = true
			return e
		&"taunt":
			# Pure marker (mirrors hunters_mark's "kind chosen loosely" precedent) — read via has_effect
			# by EnemyAI (Task 10), never edits a face.
			var e: Effect = Effect.new()
			e.id = &"taunt"; e.kind = Effect.Kind.REEL_FACE_EDIT; e.duration = 2; e.beneficial = true
			return e
		&"empowered":
			var e: Effect = Effect.new()
			e.id = &"empowered"; e.kind = Effect.Kind.MULTIPLIER_EDIT; e.magnitude = 1.4
			e.affects_incoming = false; e.duration = 2; e.beneficial = true
			return e
		&"evasion":
			var e: Effect = Effect.new()
			e.id = &"evasion"; e.kind = Effect.Kind.REEL_FACE_EDIT; e.duration = 2; e.beneficial = true
			return e
		&"regen":
			var e: Effect = Effect.new()
			e.id = &"regen"; e.kind = Effect.Kind.DAMAGE_OVER_TIME; e.duration = 3
			e.max_stacks = 3; e.dot_fractions = [0.50, 0.80, 1.15]; e.beneficial = true
			return e
		&"cursed":
			var e: Effect = Effect.new()
			e.id = &"cursed"; e.kind = Effect.Kind.DAMAGE_OVER_TIME; e.duration = 3
			e.max_stacks = 3; e.dot_fractions = [0.50, 0.80, 1.15]; e.beneficial = false
			return e
		&"haste":
			var e: Effect = Effect.new()
			e.id = &"haste"; e.kind = Effect.Kind.INITIATIVE_MOD; e.magnitude = 20.0
			e.duration = 2; e.beneficial = true
			return e
		_:
			return null
