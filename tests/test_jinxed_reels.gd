extends SceneTree

## Jinxed (Chancer "Jinx the Odds", Task 21) reel transform, tested directly against
## Combatant.jinxed_reels(): CRIT_SUCCESS -> SUCCESS, SUCCESS -> NEUTRAL/mult 0, every other tier
## untouched, non-weapon-attack reels pass through unchanged, and the original reel (and any
## shared weapon.reels) is left untouched by the deep-copy. Mirrors evasion_reels' coverage shape.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_face(tier: ReelFace.ResultTier, multiplier: float, rider: StringName = &"") -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = multiplier
	f.rider_effect_id = rider
	return f

func _init() -> void:
	# A weapon-attack reel with one face of every tier (plus a rider on the crit-success face, to
	# confirm the transform only edits tier/multiplier and leaves other face data alone).
	var reel: ActionReel = ActionReel.new()
	reel.is_weapon_attack = true
	reel.faces = [
		_make_face(ReelFace.ResultTier.CRIT_FAILURE, 0.0),
		_make_face(ReelFace.ResultTier.FAILURE, 0.0),
		_make_face(ReelFace.ResultTier.NEUTRAL, 0.0),
		_make_face(ReelFace.ResultTier.SUCCESS, 1.0),
		_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 2.0, &"some_rider"),
	]

	var out: Array[ActionReel] = Combatant.jinxed_reels([reel])
	_check(out.size() == 1, "jinxed_reels preserves reel count")
	var edited: ActionReel = out[0]

	_check(edited.faces[0].result_tier == ReelFace.ResultTier.CRIT_FAILURE, "CRIT_FAILURE untouched")
	_check(edited.faces[1].result_tier == ReelFace.ResultTier.FAILURE, "FAILURE untouched")
	_check(edited.faces[2].result_tier == ReelFace.ResultTier.NEUTRAL, "pre-existing NEUTRAL untouched")

	_check(edited.faces[3].result_tier == ReelFace.ResultTier.NEUTRAL, "SUCCESS downgraded to NEUTRAL")
	_check(edited.faces[3].multiplier == 0.0, "downgraded SUCCESS face's multiplier zeroed")

	_check(edited.faces[4].result_tier == ReelFace.ResultTier.SUCCESS, "CRIT_SUCCESS downgraded to SUCCESS")
	_check(edited.faces[4].multiplier == 1.0, "downgraded CRIT_SUCCESS face's multiplier set to 1.0")
	_check(edited.faces[4].rider_effect_id == &"some_rider", "unrelated face data (rider) untouched by the transform")

	# Original reel (and its faces) must be untouched — jinxed_reels deep-copies weapon-attack reels.
	_check(reel.faces[3].result_tier == ReelFace.ResultTier.SUCCESS, "original reel's SUCCESS face untouched (deep-copy)")
	_check(reel.faces[4].result_tier == ReelFace.ResultTier.CRIT_SUCCESS, "original reel's CRIT_SUCCESS face untouched (deep-copy)")
	_check(reel.faces[4].multiplier == 2.0, "original reel's CRIT_SUCCESS multiplier untouched (deep-copy)")
	_check(edited != reel, "returned reel is a distinct copy, not the same instance")

	# A non-weapon-attack (utility) reel passes through completely unchanged — same instance.
	var utility_reel: ActionReel = ActionReel.new()
	utility_reel.is_weapon_attack = false
	utility_reel.faces = [_make_face(ReelFace.ResultTier.SUCCESS, 1.0)]
	var out2: Array[ActionReel] = Combatant.jinxed_reels([utility_reel])
	_check(out2[0] == utility_reel, "non-weapon-attack reel passes through as the same instance, unedited")
	_check(out2[0].faces[0].result_tier == ReelFace.ResultTier.SUCCESS, "utility reel's SUCCESS face left as-is")

	# A null entry in the array is tolerated (matches evasion_reels/hunters_mark_reels null-guard).
	var out3: Array[ActionReel] = Combatant.jinxed_reels([null])
	_check(out3.size() == 1 and out3[0] == null, "null reel entries pass through unchanged")

	# Sanity against a real weapon.make_default() strip: CRIT_SUCCESS should never survive the
	# transform (it's downgraded to SUCCESS), so no face should be CRIT_SUCCESS afterward. SUCCESS
	# faces DO remain — both the pre-existing SUCCESS-turned-NEUTRAL and the former CRIT_SUCCESS
	# faces (now SUCCESS) coexist, so the tier is present but every original SUCCESS face is gone
	# with multiplier > 0 replaced by a NEUTRAL/mult-0 face instead.
	var real_reel: ActionReel = ActionReel.make_default(null)
	var real_out: Array[ActionReel] = Combatant.jinxed_reels([real_reel])
	var any_crit_success: bool = false
	for f: ReelFace in real_out[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			any_crit_success = true
	_check(not any_crit_success, "jinxed_reels leaves no CRIT_SUCCESS faces on a real default-composition reel")
	_check(real_reel.faces[0] != null, "sanity: original real_reel still intact after transform")

	quit()
