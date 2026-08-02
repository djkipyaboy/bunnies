extends SceneTree

## FishingReel + ReelFace.fishing_tier: data layer for the Fishing mini-game (2026-08-01
## gathering-profession-minigames spec section 3).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var bare: ReelFace = ReelFace.new()
	_check(bare.fishing_tier == &"", "ReelFace.fishing_tier defaults to empty StringName")

	var composition: Array = [[&"fail", 4], [&"success", 4], [&"critical", 2]]
	var reel: FishingReel = FishingReel.make_default(composition)
	_check(reel.faces.size() == 10, "make_default builds a 10-face strip from the composition's counts")

	var counts: Dictionary = {&"fail": 0, &"success": 0, &"critical": 0}
	for face: ReelFace in reel.faces:
		counts[face.fishing_tier] = counts[face.fishing_tier] + 1
	_check(counts[&"fail"] == 4, "4 fail faces built")
	_check(counts[&"success"] == 4, "4 success faces built")
	_check(counts[&"critical"] == 2, "2 critical faces built")

	# A second call builds an INDEPENDENT reel (no shared state between rounds).
	var reel2: FishingReel = FishingReel.make_default(composition)
	reel.faces[0].fishing_tier = &"mutated_for_test"
	_check(reel2.faces[0].fishing_tier != &"mutated_for_test", "make_default's two calls build independent face objects, not shared references")

	print("ok FishingReel smoke test complete")
	quit()
