class_name ActionReel
extends Reel

## An Action reel — the per-turn attack reel (DESIGN.md §4.3–§4.5).
##
## Faces resolve to the five-tier success ladder ([enum ReelFace.ResultTier]) and carry a
## damage [member ReelFace.multiplier] + optional rider. A character spins 2–5 of these in
## their Combat Phase; EACH resolves as an INDEPENDENT attack (§4.5) — no aggregation.
## Unlike [InitiativeReel], these vary by weapon/class/talent/gear — the build-expression layer.

## The damage type this reel's hits deal (Slashing/Piercing/… see [DamageType]). A turn may
## spin reels of differing types — e.g. a heavy weapon plus an ability-added Storm reel (§4.6).
@export var damage_type: DamageType

## Builds a first-pass Action reel as a physical 10-face strip. Odds = how many of each symbol
## sit on the reel (the reel IS the dice — no hidden weights). Crits are rare (1 each → 10%):
##   1 crit-failure · 2 failure · 2 neutral/utility · 4 success · 1 crit-success.
## [b]Balance numbers are [ASSUMPTION] placeholders[/b] — tune by playtest, do not hard-balance.
## (Later, gear/talents edit this symbol mix; see DESIGN.md §4.4.)
const DEFAULT_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 1],
	[ReelFace.ResultTier.FAILURE, 0.0, 2],
	[ReelFace.ResultTier.NEUTRAL, 0.0, 2],
	[ReelFace.ResultTier.SUCCESS, 1.0, 4],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 1],
]

static func make_default(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	for entry: Array in DEFAULT_COMPOSITION:
		var tier: ReelFace.ResultTier = entry[0]
		var multiplier: float = entry[1]
		var count: int = entry[2]
		for i: int in range(count):
			reel.faces.append(_make_face(tier, multiplier))
	return reel

static func _make_face(tier: ReelFace.ResultTier, multiplier: float) -> ReelFace:
	var face: ReelFace = ReelFace.new()
	face.result_tier = tier
	face.multiplier = multiplier
	return face
