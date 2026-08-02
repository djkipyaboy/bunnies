class_name ForagingMinigame
extends RefCounted

## Pure model for the Foraging "Shake the Bush" mini-game (2026-08-01
## gathering-profession-minigames spec section 2) -- a single evolving outcome tier the player can
## reroll ("shake", genuinely press-your-luck: a shake can land on a WORSE tier, no one-way-
## improvement ratchet) or bank at any time. Mirrors TeamUpMinigame's shape: no Node/UI state, fully
## headless-testable; ForagingPanel is the view.

## [ASSUMPTION] tier set (spec section 5), tuned by playtest. quality_bonus of 1 means banking this
## tier also stamps CraftingMaterial.quality_tier (the "Bumper Crop" bonus).
const TIERS: Array[Dictionary] = [
	{"name": "Meager", "quantity_multiplier": 1, "quality_bonus": 0},
	{"name": "Modest", "quantity_multiplier": 1, "quality_bonus": 0},
	{"name": "Bountiful", "quantity_multiplier": 2, "quality_bonus": 0},
	{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1},
]

## [ASSUMPTION] starting shake count, tuned by playtest.
const STARTING_SHAKES: int = 3

var shakes_remaining: int = STARTING_SHAKES
var current_tier: Dictionary
var _tiers: Array[Dictionary]

## [param p_tiers] defaults to the real TIERS pool; tests inject a smaller pool to force
## deterministic/statistically-provable outcomes (mirrors this project's "rig the reel to a known
## face" convention for other reel-driven systems).
func _init(p_tiers: Array[Dictionary] = TIERS) -> void:
	_tiers = p_tiers
	current_tier = _tiers[randi() % _tiers.size()]

## Draws a fresh, fully independent random tier -- can land on a WORSE tier than current_tier.
## No-op (returns false) once shakes_remaining is 0.
func shake() -> bool:
	if shakes_remaining <= 0:
		return false
	shakes_remaining -= 1
	current_tier = _tiers[randi() % _tiers.size()]
	return true

## Locks in current_tier and returns its outcome. Legal at any shake count, including 0.
func bank() -> Dictionary:
	return {
		"quantity_multiplier": current_tier["quantity_multiplier"],
		"quality_tier": current_tier["quality_bonus"],
		"tier_name": current_tier["name"],
	}
