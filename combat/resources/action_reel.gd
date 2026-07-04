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

## True when a HIT on this reel is a DIRECT WEAPON SWING — the normal attack reel. This is the payline
## criterion: only weapon-attack reels join the payline grid (spec 2026-06-25 §6).
##
## NOTE the distinction (the Rend case): a reel can deal weapon-TYPE damage yet NOT be a weapon ATTACK.
## Rend's hit applies a BLEED debuff that ticks for weapon-type damage over time, but the reel itself is
## a debuff-application reel, not a swing — so it sets [code]is_weapon_attack = false[/code] and stays
## OUT of paylines. GENERAL RULE for every future ability/Ultimate-added reel: set this false whenever a
## hit's purpose is utility/control (apply a buff/debuff, heal, convert), even if that effect ultimately
## deals weapon-type damage; set it true only when the hit directly swings for the weapon's damage.
@export var is_weapon_attack: bool = true

## Whether a hit on this reel charges the attacker's Bonus Meter. True for normal reels (incl. Rend).
## The Warden's Rallying Cry reel sets this FALSE: its payoff is the party shield, and it would otherwise
## let Earthquake (which already recharges fast off its 4 WILD reels) refill the meter too quickly
## (playtest 2026-06-29). The resolver propagates this onto the AttackResult; the orchestrator honors it.
@export var charges_meter: bool = true

## True only for the Ranger's Crippling Shot reel (Task 15): the orchestrator adds bonus damage
## when this reel's hit lands on a target that's Slowed/Rooted/Stunned. False for every other reel.
@export var bonus_vs_cc: bool = false

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
	# Shuffle so the strip order isn't a discoverable pattern. Balance-neutral: tier COUNTS are
	# unchanged (the reel IS the dice), only face adjacency varies — for grid/payline variety.
	reel.faces.shuffle()
	return reel

## Builds the Warrior's "Rend" reel (spec §4A/§4B): same tier spread as the default strip, but its
## HIT faces (success / crit-success) deal NO direct weapon damage (multiplier 0) and instead carry a
## &"bleed" rider. So landing a hit on this reel applies a BLEED stack rather than swinging for damage.
static func make_rend(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = make_default(type)
	reel.is_weapon_attack = false  # Rend hits apply BLEED (a debuff), not a weapon swing — out of paylines
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			face.multiplier = 0.0
			face.rider_effect_id = &"bleed"
	return reel

## Builds a real weapon-attack reel (same tier spread as make_default — the reel IS the dice, no
## odds change) whose SUCCESS/CRIT_SUCCESS faces ALSO carry [param rider_id]. Unlike make_rend
## (multiplier zeroed, utility-only), this keeps real damage: the attack itself both hits AND
## applies its rider on a hit. Used by Sundering Strike / Quake Slam / Jinx the Odds / Snare Trap /
## Hex / Entangle / Crippling Shot (spec 2026-07-01 §4).
static func make_rider_attack(type: DamageType, rider_id: StringName, bonus_vs_cc: bool = false) -> ActionReel:
	var reel: ActionReel = make_default(type)
	reel.bonus_vs_cc = bonus_vs_cc
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			face.rider_effect_id = rider_id
	return reel

## Chancer "Double or Nothing" (L9) wild gambler's reel (playtest 2026-07-04, player-specified exact
## distribution): a genuine ALL-OR-NOTHING reel — no FAILURE or NEUTRAL faces at all. A 20-face strip
## (not 10) specifically because 25%/65% aren't representable in tenths: 5 crit-failure (25%), 2
## success (10%), 13 crit-success (65%). Used for BOTH the caster's existing weapon-attack reels (via
## Combatant.gambled_reels()) and the ability's own 2 bonus reels — a whole-spin effect, not a
## partial one, matching the ability's original "wild crit-biased" framing.
const GAMBLE_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 5],
	[ReelFace.ResultTier.SUCCESS, 1.0, 2],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 13],
]

static func make_gamble(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	for entry: Array in GAMBLE_COMPOSITION:
		var tier: ReelFace.ResultTier = entry[0]
		var multiplier: float = entry[1]
		var count: int = entry[2]
		for i: int in range(count):
			reel.faces.append(_make_face(tier, multiplier))
	reel.faces.shuffle()  # balance-neutral: only adjacency varies, tier counts fixed
	return reel

## Builds the Warden's "Rallying Cry" reel (spec 2026-06-29 §3): a no-damage UTILITY reel of 2
## crit-success + 8 success faces (no fail/neutral/crit-fail). Every face deals zero direct damage
## (multiplier 0) and carries NO rider — the orchestrator reads the landed tier post-spin and shields
## the party (SUCCESS → half-weapon, CRIT_SUCCESS → full-weapon). is_weapon_attack = false → it stays
## OUT of paylines, is never WILD-biased, and sits at the loadout tail.
static func make_rallying_cry(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.is_weapon_attack = false
	reel.charges_meter = false  # the shield IS the payoff — don't also feed the Bonus Meter (playtest 2026-06-29)
	for i: int in range(2):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(8):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()  # balance-neutral: only adjacency varies, tier counts fixed
	return reel

static func _make_face(tier: ReelFace.ResultTier, multiplier: float) -> ReelFace:
	var face: ReelFace = ReelFace.new()
	face.result_tier = tier
	face.multiplier = multiplier
	return face
