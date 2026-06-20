class_name Reel
extends Resource

## Abstract base for a combat reel — the slot reel that IS the dice (DESIGN.md §2, §8).
## Holds an ordered list of [ReelFace]s and resolves a single face per [method spin].
##
## Do NOT instantiate directly. Use a subclass:
##   • [InitiativeReel] — digit 0–9 faces; a CONSTANT shared by every combatant (§4.2).
##   • [ActionReel]     — result-tier faces; VARIES by weapon/class/talent/gear (§4.4).
##
## This is pure combat DATA. Scroll/animation is a separate view concern and lives on a
## display node, not here.

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when a spin begins (before a face is selected).
signal spin_started

## Emitted once this reel resolves to a single face. [param face] is the landed [ReelFace].
signal face_resolved(face: ReelFace)

# ---------------------------------------------------------------------------
# Exported configuration
# ---------------------------------------------------------------------------

## Ordered faces on the reel strip (default 10). Edited by builds to change the odds (§2).
@export var faces: Array[ReelFace] = []

## Optional per-face selection weights, parallel to [member faces]. Empty = uniform.
## When set, its length must match [member faces]; otherwise selection falls back to uniform.
@export var weights: Array[float] = []

## The index returned by the most recent [method spin] (−1 before any spin). Used by the resolver to
## read the 3-cell visible window (top/center/bottom) for the payline grid.
var _last_index: int = -1

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Spins the reel and returns the single landed [ReelFace], emitting [signal spin_started]
## then [signal face_resolved]. Returns null only if the reel has no faces.
func spin() -> ReelFace:
	spin_started.emit()
	if faces.is_empty():
		push_warning("Reel.spin() called with no faces configured.")
		return null

	var index: int = _select_index()
	_last_index = index
	var face: ReelFace = faces[index]
	face_resolved.emit(face)
	return face

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Picks a face index — weighted if [member weights] is valid, otherwise uniform.
func _select_index() -> int:
	if weights.size() == faces.size() and not weights.is_empty():
		return _select_weighted_index()
	return randi() % faces.size()

## Weighted selection over [member weights]. Falls back to index 0 if the total is non-positive.
func _select_weighted_index() -> int:
	var total: float = 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return 0

	var roll: float = randf() * total
	var running: float = 0.0
	for i: int in range(weights.size()):
		running += maxf(weights[i], 0.0)
		if roll < running:
			return i
	return weights.size() - 1

## The face index chosen by the most recent spin() (−1 if not yet spun).
func get_last_index() -> int:
	return _last_index
