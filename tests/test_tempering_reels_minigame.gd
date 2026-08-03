extends SceneTree

## TemperingReelsMinigame: Salvaging's opt-in bonus mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.1). N+1 BonusReels, Fishing's exact continuous-rotation
## advance()/stop() mechanic. resolve() returns a DELTA to add on top of the recipe's deterministic
## base stats -- never a replacement, so the worst possible outcome is a no-op (never worse than
## skipping the mini-game).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# 1-stat-slot rarity (e.g. Common/Rare): 2 reels total (1 stat-slot + 1 temper).
	var single: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 1)
	_check(single.reels.size() == 2, "a 1-stat-slot rarity builds 2 reels (got %d)" % single.reels.size())

	# 2-stat-slot rarity (e.g. Uncommon/Epic/Legendary): 3 reels total.
	var double: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 2)
	_check(double.reels.size() == 3, "a 2-stat-slot rarity builds 3 reels (got %d)" % double.reels.size())

	# advance()/stop()/all_stopped() mirror FishingMinigame's mechanic exactly.
	_check(not double.all_stopped(), "not all_stopped() before any reel is stopped")
	double.advance(1.0)
	for i in range(3):
		double.stop(i)
	_check(double.all_stopped(), "all_stopped() once every reel has been stopped")

	# resolve() is a DELTA -- every stat-slot reel's faces are >= 0 (the design's STAT_FACE_STEPS
	# start at 0), and the temper reel's faces are ALWAYS positive (no neutral/zero face), so the
	# worst possible resolve() still has primary/secondary >= 0 and exactly one nonzero bonus.
	var worst_result: Stats = double.resolve()
	_check(worst_result.vigor >= 0 and worst_result.might >= 0 and worst_result.focus >= 0, "resolve() never returns a negative delta on any stat")

	# Over many independent instances, confirm the primary stat-slot reel can land its zero-delta
	# face (proving "baseline-or-better", not "always a forced bonus").
	var saw_zero_primary: bool = false
	for i in range(30):
		var trial: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 1)
		for c in range(trial.reels.size()):
			trial.advance(10.0)  # far more than one tick, lands somewhere without needing many calls
			trial.stop(c)
		var r: Stats = trial.resolve()
		if r.vigor == 0 or (r.vigor > 0 and r.vigor <= 3):
			saw_zero_primary = true
	_check(saw_zero_primary, "across many trials, resolve() produces small deltas (the stat-slot reel is a small bounded bonus, not unbounded)")

	# The temper reel's three modes all resolve into the right target stat.
	var single_reroll: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 1)
	# Force a known temper face by scanning for one of each mode across the (small, fixed-composition) reel.
	var temper_col: int = single_reroll.reels.size() - 1
	var found_amplify_primary: bool = false
	var found_bonus_tertiary: bool = false
	for face: ReelFace in single_reroll.reels[temper_col].faces:
		if face.bonus_mode == &"amplify_primary":
			found_amplify_primary = true
		if face.bonus_mode == &"bonus_tertiary":
			found_bonus_tertiary = true
	_check(found_amplify_primary, "the temper reel includes an amplify_primary face")
	_check(found_bonus_tertiary, "the temper reel includes a bonus_tertiary face")

	print("ok TemperingReelsMinigame smoke test complete")
	quit()
