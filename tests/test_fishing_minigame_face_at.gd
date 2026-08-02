extends SceneTree

## FishingMinigame.face_at(): reads a neighbor face relative to a reel's current index, with
## wraparound in both directions (2026-08-02 gathering-playtest-fixes spec section 2). Read-only --
## does not affect resolve() or advance()'s own behavior, covered separately in
## tests/test_fishing_minigame.gd.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _init() -> void:
	var reel: FishingReel = _reel([&"fail", &"success", &"critical"])
	var m: FishingMinigame = FishingMinigame.new([reel] as Array[FishingReel])

	_check(m.face_at(0, 0).fishing_tier == &"fail", "offset 0 matches current_face() at the starting index")
	_check(m.face_at(0, 1).fishing_tier == &"success", "offset +1 reads the next face")
	_check(m.face_at(0, -1).fishing_tier == &"critical", "offset -1 wraps to the LAST face when starting at index 0")

	m.advance(FishingMinigame.SECONDS_PER_TICK * 1.0)   # index now 1 ("success")
	_check(m.face_at(0, 0).fishing_tier == &"success", "offset 0 tracks the current index after advancing")
	_check(m.face_at(0, 1).fishing_tier == &"critical", "offset +1 reads the next face without wrapping mid-strip")
	_check(m.face_at(0, -1).fishing_tier == &"fail", "offset -1 reads the previous face without wrapping mid-strip")

	m.advance(FishingMinigame.SECONDS_PER_TICK * 1.0)   # index now 2 ("critical", the last index)
	_check(m.face_at(0, 1).fishing_tier == &"fail", "offset +1 wraps back to the FIRST face when at the last index")

	print("ok FishingMinigame.face_at smoke test complete")
	quit()
