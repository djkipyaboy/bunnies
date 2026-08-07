class_name SecondHelpingMinigame
extends RefCounted

## Pure model for Cooking's opt-in "Second Helping" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2). reel_count BonusReels (recipe-authored via
## RecipeLibrary.cooking_recipes()'s bonus_reel_count, default 1 so a future recipe can specify more
## without any engine change), each independently picking &"baseline" (0) or &"bonus_quantity" (extra
## units). Mirrors ForagingMinigame's shape: an evolving pick, a CAPPED reroll pool (exactly 1, not
## Foraging's 3, per player direction), and bank(). Never worse than skipping the mini-game entirely
## (skipping = 0 reels = 0 bonus; every reel's worst face is baseline = 0, never negative).

const REEL_COMPOSITION: Array = [
	[&"baseline", 0, 3],
	[&"bonus_quantity", 1, 1],
]

var reels: Array[BonusReel] = []
var rerolls_remaining: int = 1
var _current_faces: Array[ReelFace] = []

func _init(reel_count: int) -> void:
	for i in range(reel_count):
		reels.append(BonusReel.make_default(REEL_COMPOSITION))
	_draw()

func _draw() -> void:
	_current_faces.clear()
	for reel: BonusReel in reels:
		_current_faces.append(reel.faces[randi() % reel.faces.size()])

func current_faces() -> Array[ReelFace]:
	return _current_faces.duplicate()

## Draws a genuinely fresh face for every reel — can land better or worse than the current pick, but
## never below the design's floor of 0 (there is no negative face). No-op (returns false) once
## rerolls_remaining is 0.
func reroll() -> bool:
	if rerolls_remaining <= 0:
		return false
	rerolls_remaining -= 1
	_draw()
	return true

## Locks in the current picks and returns the total bonus quantity across every reel. Legal at any
## reroll count, including 0.
func bank() -> int:
	var total: int = 0
	for face: ReelFace in _current_faces:
		if face.bonus_mode == &"bonus_quantity":
			total += int(face.bonus_magnitude)
	return total
