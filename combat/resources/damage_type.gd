class_name DamageType
extends Resource

## One of the six damage types and its row of the type chart (DESIGN.md §5).
## Replaces the old casino PayTable: there are no paylines — damage is a per-face multiplier
## (on [ReelFace]) followed by this type-chart lookup.
##
## The six types are Slashing · Piercing · Crushing · Storm · Mystic · Earth. Spread is gentle
## (×0.75 / ×1.0 / ×1.25, rare ×0.5 / ×1.5) so type is A factor, not THE factor. Actual chart
## values are a next-session deliverable (DESIGN.md §12); this resource just stores a row.

## Canonical type ids. Stored as the chart keys so a [DamageType] is fully data-driven.
enum Type { SLASHING, PIERCING, CRUSHING, STORM, MYSTIC, EARTH }

## This type's identity.
@export var type: Type = Type.SLASHING

## Inherent rider this type tends to carry, e.g. Crushing → Slow (DESIGN.md §4.6). Empty = none.
@export var inherent_rider_id: StringName = &""

## This type's row of the chart: defending [enum Type] (as int) → damage multiplier.
## Any defender absent from the dictionary uses [member default_multiplier].
@export var effectiveness: Dictionary = {}

## Multiplier used against a defender not listed in [member effectiveness] (neutral matchup).
@export var default_multiplier: float = 1.0

## Returns this type's damage multiplier against [param defender] (DESIGN.md §5.1 lookup).
func multiplier_against(defender: DamageType) -> float:
	if defender == null:
		return default_multiplier
	return effectiveness.get(defender.type, default_multiplier) as float
