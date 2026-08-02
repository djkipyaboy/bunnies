extends SceneTree

## ForagingMinigame: pure model for the "Shake the Bush" mini-game (2026-08-01
## gathering-profession-minigames spec section 2). No Node/UI state -- fully headless.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Default construction (real TIERS pool) always produces a valid drawn tier immediately.
	var m: ForagingMinigame = ForagingMinigame.new()
	_check(ForagingMinigame.TIERS.has(m.current_tier), "construction immediately draws a real tier from TIERS")
	_check(m.shakes_remaining == 3, "starts with 3 shakes remaining")

	# Rigged to a single tier: current_tier is always exactly that tier, both at construction and
	# after every shake (proves the model consumes whatever pool it's given, not the real TIERS).
	var meager: Dictionary = {"name": "Meager", "quantity_multiplier": 1, "quality_bonus": 0}
	var single: ForagingMinigame = ForagingMinigame.new([meager])
	_check(single.current_tier == meager, "a 1-tier pool always draws that tier at construction")
	_check(single.shake(), "shake() returns true while shakes remain")
	_check(single.current_tier == meager, "a 1-tier pool always draws that tier after shake() too")
	_check(single.shakes_remaining == 2, "shake() decrements shakes_remaining")

	# Exhausting shakes: shake() becomes a no-op (returns false) at 0, and bank() is still legal.
	var exhausted: ForagingMinigame = ForagingMinigame.new([meager])
	exhausted.shake()
	exhausted.shake()
	exhausted.shake()
	_check(exhausted.shakes_remaining == 0, "3 shakes fully exhausts the starting pool")
	_check(not exhausted.shake(), "shake() at 0 remaining returns false (no-op)")
	var banked_at_zero: Dictionary = exhausted.bank()
	_check(banked_at_zero["quantity_multiplier"] == 1, "bank() is legal at 0 shakes remaining")

	# A shake can land on a WORSE tier than the current one -- proven statistically over many
	# independent draws from a 2-tier pool (both this project's Reel-selection tests and its
	# ActionReel weighted-face tests use this exact "many trials, assert both outcomes appear"
	# technique in place of seeding the RNG directly).
	var bountiful: Dictionary = {"name": "Bountiful", "quantity_multiplier": 2, "quality_bonus": 0}
	var seen_names: Dictionary = {}
	for i in range(50):
		var trial: ForagingMinigame = ForagingMinigame.new([bountiful, meager])
		seen_names[trial.current_tier["name"]] = true
	_check(seen_names.has("Meager") and seen_names.has("Bountiful"), "over 50 independent draws from a 2-tier pool, both tiers appear (no one-way-improvement ratchet)")

	# bank() returns the full outcome contract the spec defines, including the quality bonus tier.
	var bumper: Dictionary = {"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}
	var bumper_game: ForagingMinigame = ForagingMinigame.new([bumper])
	var outcome: Dictionary = bumper_game.bank()
	_check(outcome["quantity_multiplier"] == 2, "bank() reports the tier's quantity_multiplier")
	_check(outcome["quality_tier"] == 1, "bank() reports the tier's quality bonus as quality_tier")
	_check(outcome["tier_name"] == "Bumper Crop", "bank() reports the tier's display name")

	print("ok ForagingMinigame smoke test complete")
	quit()
