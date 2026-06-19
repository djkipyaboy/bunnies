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
