class_name ReelFace
extends Resource

## A single face on a [Reel]. Inspector-editable so faces can be authored as data.
##
## One [ReelFace] type serves both reel kinds (a deliberate "nullable fields" choice,
## see DESIGN.md §8): an [ActionReel] face uses [member result_tier] / [member multiplier]
## / [member rider_effect_id]; an [InitiativeReel] face uses [member digit]. The fields
## for the other kind are simply left at their defaults.

## The five standard outcomes of an Action reel, lowest → highest (DESIGN.md §4.4).
## NEUTRAL deals no damage — it is a utility result that still charges the Bonus Meter.
enum ResultTier {
	CRIT_FAILURE,
	FAILURE,
	NEUTRAL,
	SUCCESS,
	CRIT_SUCCESS,
}

# ---------------------------------------------------------------------------
# Action-reel fields
# ---------------------------------------------------------------------------

## Which success-ladder tier this face resolves to (Action reels only).
@export var result_tier: ResultTier = ResultTier.SUCCESS

## Multiplier applied to weapon base damage when this face lands (DESIGN.md §4.5).
## NEUTRAL/FAILURE/CRIT_FAILURE faces deal no damage regardless — see [method deals_damage].
@export var multiplier: float = 1.0

## Optional id of a rider [Effect] this face applies (buff/debuff/DoT). Empty = none.
@export var rider_effect_id: StringName = &""

# ---------------------------------------------------------------------------
# Initiative-reel field
# ---------------------------------------------------------------------------

## Digit 0–9 for an [InitiativeReel] face (DESIGN.md §4.2). Left at -1 on Action faces.
@export_range(-1, 9) var digit: int = -1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## True if this Action face produces weapon damage. NEUTRAL and the failure tiers do not;
## their value is utility and Bonus-Meter charge (DESIGN.md §4.4).
func deals_damage() -> bool:
	return result_tier == ResultTier.SUCCESS or result_tier == ResultTier.CRIT_SUCCESS
