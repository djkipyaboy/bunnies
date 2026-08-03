class_name BonusReel
extends Reel

## The shared reel engine for both new profession mini-games (2026-08-02 salvaging-and-cooking
## professions design section 6) -- a fifth Reel sibling (Initiative/Action/TeamUp/Fishing). Faces
## carry bonus_mode/bonus_magnitude, not result_tier/team_up_symbol/fishing_tier.
##
## Deliberately adds NO spin()/_select_index() override, matching FishingReel's precedent -- neither
## TemperingReelsMinigame nor SecondHelpingMinigame ever calls spin() on a BonusReel; both read
## faces[] directly (TemperingReelsMinigame via Fishing's continuous-rotation advance()/stop()
## mechanic, SecondHelpingMinigame via a single fresh random pick per spin/reroll).

## Builds a reel from [param composition], an Array of [mode: StringName, magnitude: int, count: int]
## triples -- mirrors FishingReel.make_default()'s [tier, count] shape with an added magnitude column.
static func make_default(composition: Array) -> BonusReel:
	var reel: BonusReel = BonusReel.new()
	for entry: Array in composition:
		var mode: StringName = entry[0]
		var magnitude: int = entry[1]
		var count: int = entry[2]
		# Structural guardrail (final-review finding, 2026-08-02): TemperingReelsMinigame's whole
		# "opting in is never worse than skipping" guarantee depends on every BonusReel face being
		# >= 0 -- make that an assertion here, not just a convention any future composition (e.g.
		# Cooking's reuse of this class) has to remember to honor by hand.
		assert(magnitude >= 0, "BonusReel faces must never be negative — the never-worse-than-skipping invariant depends on this")
		for i in range(count):
			var face: ReelFace = ReelFace.new()
			face.bonus_mode = mode
			face.bonus_magnitude = magnitude
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel
