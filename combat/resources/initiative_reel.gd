class_name InitiativeReel
extends Reel

## The Initiative reel — a single 10-sided digit reel (faces 0–9), DESIGN.md §4.2.
##
## This reel is a CONSTANT shared by every combatant: build one [InitiativeReel] (or load a
## single shared .tres) and reuse it. Two of them form the d100 percentile spin — reel 1 = tens,
## reel 2 = ones. Talents/gear that bias initiative do so by editing a combatant's own copy's
## faces (e.g. replacing a 0 with another 9), not by changing this base behaviour.

## Builds a standard 0–9 digit reel. Convenience for the shared default; faces stay editable.
static func make_default() -> InitiativeReel:
	var reel: InitiativeReel = InitiativeReel.new()
	for d: int in range(10):
		var face: ReelFace = ReelFace.new()
		face.digit = d
		reel.faces.append(face)
	return reel

## Rolls a full percentile result from a [param tens] reel and a [param ones] reel.
## Applies the confirmed convention: a raw 00 reads as 100 (the top/critical roll); 01 is the
## true minimum. Effective range 1–100, uniform (DESIGN.md §4.2).
static func roll_percentile(tens: InitiativeReel, ones: InitiativeReel) -> int:
	var raw: int = tens.spin().digit * 10 + ones.spin().digit
	if raw == 0:
		return 100
	return raw

## Recovers the (tens, ones) digit pair for a raw percentile [param value] (1-100, 00-as-100
## convention), so a visual strip can be told which face index to land on WITHOUT needing the
## actual spun Reel instance (roll_initiative() spins the SAME shared tens/ones reels
## sequentially for every combatant, so by animation time only the last spin's landed face
## survives on those shared objects). Since make_default() builds faces in strict digit order
## (faces[i].digit == i), a digit IS its own face index on a fresh make_default() reel.
## 2026-08-16 visible-initiative-reels spec §2.
static func digits_for_value(value: int) -> Vector2i:
	if value == 100:
		return Vector2i(0, 0)
	return Vector2i(value / 10, value % 10)
