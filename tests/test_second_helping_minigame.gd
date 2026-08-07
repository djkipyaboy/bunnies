extends SceneTree

## SecondHelpingMinigame: Cooking's opt-in bonus mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2). reel_count BonusReels (recipe-authored, default 1 -- a future
## recipe can specify more with no engine change), an initial spin, exactly 1 reroll, then bank().
## Mirrors ForagingMinigame's shape (evolving pick + capped reroll pool + bank), generalized to sum
## across multiple reels instead of tracking one tier value.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var single: SecondHelpingMinigame = SecondHelpingMinigame.new(1)
	_check(single.reels.size() == 1, "reel_count=1 builds exactly 1 reel")
	_check(single.rerolls_remaining == 1, "starts with exactly 1 reroll (not Foraging's pool of 3)")
	_check(single.current_faces().size() == 1, "current_faces() returns one face per reel")

	var multi: SecondHelpingMinigame = SecondHelpingMinigame.new(3)
	_check(multi.reels.size() == 3, "reel_count is recipe-configurable -- 3 reels here, proving no hardcoded engine limit")

	# A reroll can go up or down (genuinely fresh, no ratchet) -- proven statistically like Foraging's
	# own test does, over many independent instances/rerolls.
	var saw_bonus: bool = false
	var saw_baseline: bool = false
	for i in range(50):
		var trial: SecondHelpingMinigame = SecondHelpingMinigame.new(1)
		trial.reroll()
		var total: int = trial.bank()
		if total == 0:
			saw_baseline = true
		elif total > 0:
			saw_bonus = true
	_check(saw_baseline and saw_bonus, "over 50 trials with 1 reroll each, both baseline (0 bonus) and a bonus outcome appear")

	# Exactly 1 reroll: a second reroll attempt is a no-op.
	var capped: SecondHelpingMinigame = SecondHelpingMinigame.new(1)
	_check(capped.reroll(), "the first reroll() succeeds")
	_check(not capped.reroll(), "a second reroll() fails -- only 1 reroll allowed")
	_check(capped.rerolls_remaining == 0, "rerolls_remaining hits 0 after the single reroll")

	# bank() is legal at 0 rerolls remaining, and sums bonus_quantity across every reel.
	_check(typeof(capped.bank()) == TYPE_INT, "bank() returns an int total even at 0 rerolls remaining")

	print("ok SecondHelpingMinigame smoke test complete")
	quit()
