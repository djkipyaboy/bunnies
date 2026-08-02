class_name FishingMinigame
extends RefCounted

## Pure model for the Fishing reel-stop mini-game (2026-08-01 gathering-profession-minigames spec
## section 3) -- N FishingReels (N=1/3/5) rotate continuously; the player stops each individually,
## in any order. Unlike every other Reel consumer in this codebase (which calls spin() for an
## instant result), this drives CONTINUOUS rotation via advance(delta) and captures whatever face
## is showing at the moment of stop(col). Mirrors TeamUpMinigame/ForagingMinigame's shape: no
## Node/UI state, fully headless-testable; FishingPanel is the view.

## [ASSUMPTION] seconds per face-advance tick, tuned at playtest (spec section 3 -- rotation speed
## explicitly deferred to playtest, not designed now).
const SECONDS_PER_TICK: float = 0.15

var reels: Array[FishingReel] = []
var _current_indices: Array[int] = []
var _stopped: Array[bool] = []
var _elapsed: Array[float] = []

func _init(p_reels: Array[FishingReel]) -> void:
	reels = p_reels
	for i in range(reels.size()):
		_current_indices.append(0)
		_stopped.append(false)
		_elapsed.append(0.0)

## Advances every UN-STOPPED reel's displayed index by however many whole ticks [param delta]
## covers (leftover fractional time carries over per-reel, so a slow/irregular caller doesn't lose
## ticks). No-op on any reel already stopped.
func advance(delta: float) -> void:
	for i in range(reels.size()):
		if _stopped[i]:
			continue
		_elapsed[i] += delta
		while _elapsed[i] >= SECONDS_PER_TICK:
			_elapsed[i] -= SECONDS_PER_TICK
			_current_indices[i] = (_current_indices[i] + 1) % reels[i].faces.size()

## The face currently displayed on reel [param col] (whether still rotating or already stopped).
func current_face(col: int) -> ReelFace:
	return reels[col].faces[_current_indices[col]]

func is_stopped(col: int) -> bool:
	return _stopped[col]

## Freezes reel [param col] at whatever face is CURRENTLY showing and returns it. Calling this
## again on an already-stopped reel is a no-op that returns the same frozen face.
func stop(col: int) -> ReelFace:
	_stopped[col] = true
	return current_face(col)

## True once every reel has been stopped.
func all_stopped() -> bool:
	return not _stopped.has(false)

## Resolution ladder (spec section 3): catch/no-catch + quantity/quality bonus, once all_stopped().
## Meaningless before that -- callers must check all_stopped() first.
##
## LOCKED RULE (do not remove the `total > 1` guard): a 1-reel fish has no separate
## quantity-only bonus tier -- "all positive, not all critical" is indistinguishable from a plain
## win when there's only one reel, so that tier must never fire at total == 1. Only an all-Critical
## result grants a bonus on a 1-reel fish.
func resolve() -> Dictionary:
	var total: int = reels.size()
	var positive_count: int = 0
	var critical_count: int = 0
	for i in range(total):
		var tier: StringName = current_face(i).fishing_tier
		if tier == &"success" or tier == &"critical":
			positive_count += 1
		if tier == &"critical":
			critical_count += 1

	var threshold: int = _catch_threshold(total)
	var caught: bool = positive_count >= threshold
	var quantity_multiplier: int = 1
	var quality_tier: int = 0
	if caught:
		if critical_count == total:
			quantity_multiplier = 2
			quality_tier = 1
		elif total > 1 and positive_count == total:
			quantity_multiplier = 2
	return {"caught": caught, "quantity_multiplier": quantity_multiplier, "quality_tier": quality_tier}

## [ASSUMPTION] catch thresholds (spec section 3): 1-reel needs its own win, 3-reel needs 2 of 3,
## 5-reel needs 3 of 5. Every real fish is one of these three sizes.
static func _catch_threshold(total: int) -> int:
	match total:
		1: return 1
		3: return 2
		5: return 3
		_: return total
