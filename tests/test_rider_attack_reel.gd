extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var reel: ActionReel = ActionReel.make_rider_attack(null, &"sundered")
	_check(reel.is_weapon_attack, "make_rider_attack reel joins paylines (unlike Rend)")
	var hit_count: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			hit_count += 1
			_check(f.multiplier > 0.0, "hit face keeps real damage multiplier")
			_check(f.rider_effect_id == &"sundered", "hit face carries the requested rider")
	_check(hit_count == 5, "5 hit faces (4 success + 1 crit-success), matching DEFAULT_COMPOSITION")

	var cc_reel: ActionReel = ActionReel.make_rider_attack(null, &"weakened", true)
	_check(cc_reel.bonus_vs_cc, "bonus_vs_cc flag set when requested")
	var plain_reel: ActionReel = ActionReel.make_rider_attack(null, &"rooted")
	_check(not plain_reel.bonus_vs_cc, "bonus_vs_cc defaults false")
	quit()
