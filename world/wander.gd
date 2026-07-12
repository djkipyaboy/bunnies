class_name Wander
extends RefCounted

## Shared wander-target math (extracted from Villager so other wandering world NPCs can reuse it
## without depending on the Villager class). Pure/static/deterministic — see docs/superpowers/
## specs/2026-07-11-overworld-npc-encounters-design.md §3.2.

## Picks a point within leash_radius of origin, given an explicit angle and distance
## fraction (both supplied by the caller so this stays a pure, deterministic,
## unit-testable function — the caller is responsible for supplying randomness).
static func random_target(origin: Vector2, leash_radius: float, angle: float, distance_fraction: float) -> Vector2:
	var clamped_fraction: float = clampf(distance_fraction, 0.0, 1.0)
	return origin + Vector2(cos(angle), sin(angle)) * leash_radius * clamped_fraction
