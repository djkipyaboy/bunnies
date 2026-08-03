extends SceneTree

## BonusReel: the shared reel engine for Salvaging's Tempering Reels and Cooking's Second Helping
## (2026-08-02 salvaging-and-cooking professions design section 6). A fifth Reel sibling
## (Initiative/Action/TeamUp/Fishing) — faces carry bonus_mode/bonus_magnitude, not
## result_tier/team_up_symbol/fishing_tier.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var reel: BonusReel = BonusReel.make_default([
		[&"stat_value", 0, 2],
		[&"stat_value", 1, 1],
	])
	_check(reel.faces.size() == 3, "make_default() builds one face per count entry (got %d)" % reel.faces.size())

	var zero_count: int = 0
	var one_count: int = 0
	for face: ReelFace in reel.faces:
		_check(face.bonus_mode == &"stat_value", "every face carries the composition's mode")
		if face.bonus_magnitude == 0:
			zero_count += 1
		elif face.bonus_magnitude == 1:
			one_count += 1
	_check(zero_count == 2, "2 faces at magnitude 0 (got %d)" % zero_count)
	_check(one_count == 1, "1 face at magnitude 1 (got %d)" % one_count)

	# Deliberately NOT called: BonusReel adds no spin() override, matching FishingReel's precedent —
	# neither mini-game ever spins it; both read faces[] directly. Nothing to assert here beyond
	# "the class exists and extends Reel", proven by make_default() succeeding above.
	_check(reel is Reel, "BonusReel extends the shared Reel base")

	print("ok BonusReel smoke test complete")
	quit()
