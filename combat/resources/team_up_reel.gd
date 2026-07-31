class_name TeamUpReel
extends Reel

## The Team-Up! bonus-round reel — a third sibling of InitiativeReel/ActionReel (2026-07-29 spec
## §4). CLAUDE.md §2's "two subclasses" rule describes why a shared enum-based class is wrong (the
## two existing kinds carry genuinely different face data), not a hard cap of two — this kind's
## faces carry team_up_symbol, not result_tier/multiplier.
##
## Deliberately adds NO spin()/_select_index() override: Reel.spin() already returns one
## independently-drawn face per call. TeamUpMinigame fills a column's 3 rows with THREE separate
## spin() calls on this same reel object, rather than deriving 3 rows from one landed index via
## strip adjacency the way CombatResolver._build_grid() does for ActionReel — that adjacency
## approach can't support "lock one row, re-spin the others on the same reel," which this design
## requires (spec §4).

## Builds a reel from [param composition], an Array of [symbol: StringName, count: int] pairs.
static func make_default(composition: Array) -> TeamUpReel:
	var reel: TeamUpReel = TeamUpReel.new()
	for entry: Array in composition:
		var symbol: StringName = entry[0]
		var count: int = entry[1]
		for i: int in range(count):
			var face: ReelFace = ReelFace.new()
			face.team_up_symbol = symbol
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel
