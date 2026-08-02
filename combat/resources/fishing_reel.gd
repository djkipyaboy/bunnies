class_name FishingReel
extends Reel

## The Fishing mini-game's reel (2026-08-01 gathering-profession-minigames spec section 3) -- a
## fourth Reel sibling (InitiativeReel/ActionReel/TeamUpReel). Faces carry fishing_tier, not
## result_tier/team_up_symbol/digit.
##
## Deliberately adds NO spin()/_select_index() override, and nothing ever CALLS spin() on a
## FishingReel: FishingMinigame reads faces[] directly by index to drive its own
## continuous-rotation advance()/stop() mechanic -- a consumption pattern distinct from every other
## reel in this codebase, which all resolve instantly via spin().

## Builds a reel from [param composition], an Array of [tier: StringName, count: int] pairs.
static func make_default(composition: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for entry: Array in composition:
		var tier: StringName = entry[0]
		var count: int = entry[1]
		for i in range(count):
			var face: ReelFace = ReelFace.new()
			face.fishing_tier = tier
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel
