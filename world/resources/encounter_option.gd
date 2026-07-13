class_name EncounterOption
extends Resource

## One selectable choice within a RandomEncounter (player direction 2026-07-12, Slay-the-Spire-
## style "?" overworld node) — resolved via a REEL SPIN, not a plain probability roll, to stay
## on-theme with the game's core mechanic (the reel IS the dice, CLAUDE.md Pillar 1). Every
## numeric magnitude here is [ASSUMPTION] — tune by playtest, this is the framework, not balance.

## Buckets the five-tier ActionReel result ladder into a 3-way encounter outcome — critfail/fail
## collapse to BAD, neutral stays NEUTRAL (no-op, "nothing happens"), success/critsuccess collapse
## to GOOD. Pure/static so it's unit-testable without spinning a real reel.
enum Outcome { BAD, NEUTRAL, GOOD }

@export var label: String = ""
@export var reel: ActionReel

@export var bad_text: String = ""
@export var neutral_text: String = ""
@export var good_text: String = ""

## Flat deltas applied to the PC on resolution — positive hp_delta heals, negative damages
## (Combatant.heal()/take_damage()). Kept minimal (gold + PC HP only) for this playtest; not a
## general effect system.
@export var bad_gold_delta: int = 0
@export var bad_hp_delta: int = 0
@export var neutral_gold_delta: int = 0
@export var neutral_hp_delta: int = 0
@export var good_gold_delta: int = 0
@export var good_hp_delta: int = 0

static func bucket_for(tier: ReelFace.ResultTier) -> Outcome:
	match tier:
		ReelFace.ResultTier.CRIT_FAILURE, ReelFace.ResultTier.FAILURE:
			return Outcome.BAD
		ReelFace.ResultTier.SUCCESS, ReelFace.ResultTier.CRIT_SUCCESS:
			return Outcome.GOOD
		_:
			return Outcome.NEUTRAL

func text_for(outcome: Outcome) -> String:
	match outcome:
		Outcome.BAD: return bad_text
		Outcome.GOOD: return good_text
		_: return neutral_text

func gold_delta_for(outcome: Outcome) -> int:
	match outcome:
		Outcome.BAD: return bad_gold_delta
		Outcome.GOOD: return good_gold_delta
		_: return neutral_gold_delta

func hp_delta_for(outcome: Outcome) -> int:
	match outcome:
		Outcome.BAD: return bad_hp_delta
		Outcome.GOOD: return good_hp_delta
		_: return neutral_hp_delta
