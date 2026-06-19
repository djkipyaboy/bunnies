class_name BonusMeter
extends RefCounted

## A combatant's Bonus Meter — a SEPARATE economy from Stamina/Focus/Mana (DESIGN.md §4.9).
## Action-reel results charge it; at [member cap] it is "armed" and its Ultimate can fire (firing
## is deferred for the prototype). Per-class [member floor] governs carryover between combats.
##
## Exists only for PCs and Elite/Boss enemies. Enemy meters are hidden unless [member is_visible].

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever [member value] changes, for UI binding.
signal meter_changed(value: int, cap: int)

## Emitted once when the meter first reaches [member cap] (becomes armed).
signal meter_armed

# ---------------------------------------------------------------------------
# Configuration  ([ASSUMPTION] placeholders — tune by playtest, DESIGN.md §4.9)
# ---------------------------------------------------------------------------

## Maximum charge. At this value the meter is armed.
var cap: int = 10

## Per-class carryover threshold (DESIGN.md §4.9). See [method resolve_post_combat].
var floor: int = 0

## Charge gained per result tier, indexed by [enum ReelFace.ResultTier].
## First pass: crit-fail 0, fail 0, neutral +1, success +2, crit-success +3.
var charge_weights: Array[int] = [0, 0, 1, 2, 3]

## Whether the player can see this meter (false for non-Elite enemies by default).
var is_visible: bool = true

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var value: int = 0

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Adds this result tier's charge weight, clamped to [member cap]. Emits [signal meter_changed],
## and [signal meter_armed] the first time the meter reaches the cap.
func charge(tier: ReelFace.ResultTier) -> void:
	var was_armed: bool = is_armed()
	var gain: int = 0
	if tier >= 0 and tier < charge_weights.size():
		gain = charge_weights[tier]
	if gain == 0:
		return  # No change — don't churn signals.

	value = mini(value + gain, cap)
	meter_changed.emit(value, cap)
	if is_armed() and not was_armed:
		meter_armed.emit()

## True when the meter is full and its Ultimate is armed.
func is_armed() -> bool:
	return value >= cap

## Spends the full meter (firing the Ultimate). Cost is the meter only (DESIGN.md §4.9).
func consume() -> void:
	value = 0
	meter_changed.emit(value, cap)

## Applies the post-combat carryover rule (DESIGN.md §4.9):
##   • below floor      → resets to 0
##   • floor ≤ value < cap → resets down to floor (partial charge retained)
##   • full (== cap)    → stays full, carries into the next encounter
func resolve_post_combat() -> void:
	if value >= cap:
		pass
	elif value >= floor:
		value = floor
	else:
		value = 0
	meter_changed.emit(value, cap)
