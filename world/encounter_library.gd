class_name EncounterLibrary
extends RefCounted

## Code registry of authored RandomEncounters (player direction 2026-07-12) — mirrors
## ClassLibrary/EnemyLibrary/EffectLibrary: returns a FRESH RandomEncounter each call. One
## authored example for this playtest (the player's own bandit-ambush scenario); more encounters
## are future content, not a framework gap.

const IDS: Array[StringName] = [&"bandit_ambush"]

static func make(id: StringName) -> RandomEncounter:
	match id:
		&"bandit_ambush":
			var e: RandomEncounter = RandomEncounter.new()
			e.id = id
			e.description = "A band of bandits blocks the road ahead, weapons drawn. What do you do?"
			e.options = [_duel_option(), _flee_option(), _negotiate_option()]
			return e
		_:
			return null

static func _duel_option() -> EncounterOption:
	var o: EncounterOption = EncounterOption.new()
	o.label = "Challenge their leader to a duel"
	o.reel = ActionReel.make_default()   # highest variance of the three — a real fight
	o.good_text = "You best the bandit leader in single combat — the rest scatter, dropping their coin purse."
	o.neutral_text = "The duel ends in a draw. Both sides back away; nothing gained or lost."
	o.bad_text = "You're overpowered and beaten badly before the bandits let you limp away."
	o.good_gold_delta = 15
	o.bad_hp_delta = -20
	return o

static func _flee_option() -> EncounterOption:
	var o: EncounterOption = EncounterOption.new()
	o.label = "Cause a distraction and attempt to flee"
	o.reel = _social_reel()
	o.good_text = "Your distraction works — the party slips away clean."
	o.neutral_text = "You get away, but not before a bandit gets in one solid hit."
	o.bad_text = "The distraction fails and the bandits catch you before you can escape."
	o.neutral_hp_delta = -5
	o.bad_hp_delta = -10
	return o

static func _negotiate_option() -> EncounterOption:
	var o: EncounterOption = EncounterOption.new()
	o.label = "Convince them to let you pass"
	o.reel = _social_reel()
	o.good_text = "Your words (and a little coin) buy safe passage."
	o.neutral_text = "They let you pass, but not before emptying a few coins from your pockets."
	o.bad_text = "They see through the bluff and rough up the party before letting you go."
	o.neutral_gold_delta = -5
	o.bad_gold_delta = -10
	o.bad_hp_delta = -5
	return o

## A gentler spread than ActionReel.make_default() — fewer crit-fails, since these are
## non-combat social/evasion checks, not a weapon swing. [ASSUMPTION].
const SOCIAL_COMPOSITION := [
	[ReelFace.ResultTier.FAILURE, 2],
	[ReelFace.ResultTier.NEUTRAL, 3],
	[ReelFace.ResultTier.SUCCESS, 4],
	[ReelFace.ResultTier.CRIT_SUCCESS, 1],
]

static func _social_reel() -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	for entry: Array in SOCIAL_COMPOSITION:
		var tier: ReelFace.ResultTier = entry[0]
		var count: int = entry[1]
		for i: int in range(count):
			var f: ReelFace = ReelFace.new()
			f.result_tier = tier
			reel.faces.append(f)
	reel.faces.shuffle()
	return reel
