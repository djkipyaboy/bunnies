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

## True only for the Vanguard's Quake Slam reel when its "Heavier Slam" Ability Talent is picked
## (Task 16): the orchestrator attaches a SECOND stack of this reel's rider effect immediately on a
## hit, rather than the usual single stack. False for every other reel.
@export var talent_extra_rider_stack: bool = false

## True only for the Ranger's Crippling Shot reel (Task 15): the orchestrator adds bonus damage
## when this reel's hit lands on a target that's Slowed/Rooted/Stunned. False for every other reel.
@export var bonus_vs_cc: bool = false

## Builds a first-pass Action reel as a physical 50-face strip (scaled 5x from the original 10,
## 2026-08-13 accuracy-stat spec §2 — gives Luck/Finesse's per-point face conversions real
## percentage granularity without eliminating a tier entirely). Odds = how many of each symbol sit
## on the reel (the reel IS the dice — no hidden weights). Crits are rare (5 each → 10%):
##   5 crit-failure · 10 failure · 10 neutral/utility · 20 success · 5 crit-success.
## [b]Balance numbers are [ASSUMPTION] placeholders[/b] — tune by playtest, do not hard-balance.
## (Later, gear/talents edit this symbol mix; see DESIGN.md §4.4.)
const DEFAULT_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 5],
	[ReelFace.ResultTier.FAILURE, 0.0, 10],
	[ReelFace.ResultTier.NEUTRAL, 0.0, 10],
	[ReelFace.ResultTier.SUCCESS, 1.0, 20],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 5],
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

## Builds the Warrior's "Rend" reel (spec §4A/§4B): derives from ABILITY_COMPOSITION (2026-08-13
## accuracy-stat spec §2 — Rend is a resource-costed ability that adds a reel, same as every other
## reel in that spec's scope), but its HIT faces (success / crit-success) deal NO direct weapon
## damage (multiplier 0) and instead carry a &"bleed" rider. So landing a hit on this reel applies
## a BLEED stack rather than swinging for damage.
static func make_rend(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = make_ability_attack(type)
	reel.is_weapon_attack = false  # Rend hits apply BLEED (a debuff), not a weapon swing — out of paylines
	for face: ReelFace in reel.faces:
		if face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			face.multiplier = 0.0
			face.rider_effect_id = &"bleed"
	return reel

## The shared composition for every reel that exists because of a resource-costed ability — NOT
## the plain weapon-swing baseline (2026-08-13 accuracy-stat spec §2, replacing the old
## RIDER_COMPOSITION/make_rider_attack "called shot" concept). Removes the NEUTRAL tier entirely
## (player's own least-favorite thing about combat: spending a resource and landing on a
## no-damage utility result) and redistributes what used to be neutral into fail/success so the
## base hit rate lands at 70% (before Finesse/Luck conversion): 5 crit-failure · 10 failure ·
## 30 success · 5 crit-success, out of 50 faces. [ASSUMPTION] tune by playtest, same as
## DEFAULT_COMPOSITION.
const ABILITY_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 5],
	[ReelFace.ResultTier.FAILURE, 0.0, 10],
	[ReelFace.ResultTier.SUCCESS, 1.0, 30],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 5],
]

## Builds a real weapon-attack reel using ABILITY_COMPOSITION's more-reliable odds (see its comment)
## rather than DEFAULT_COMPOSITION — every reel that exists because of a resource-costed ability
## uses this, whether or not it carries a rider. When [param rider_id] is non-empty, it's attached
## to every SUCCESS/CRIT_SUCCESS face (the attack both hits AND applies its rider on a hit). Used by
## Flurry, Rend (via make_rend), Select Fate, Sundering Strike, Quake Slam, Jinx the Odds, Snare
## Trap, Hex, Entangle, Crippling Shot, Mana Surge, Rampage, Collateral Damage, Big Bang, and
## Earthquake (spec 2026-08-13 §2).
static func make_ability_attack(type: DamageType, rider_id: StringName = &"", bonus_vs_cc: bool = false) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.bonus_vs_cc = bonus_vs_cc
	for entry: Array in ABILITY_COMPOSITION:
		var tier: ReelFace.ResultTier = entry[0]
		var multiplier: float = entry[1]
		var count: int = entry[2]
		for i: int in range(count):
			var face: ReelFace = _make_face(tier, multiplier)
			if rider_id != &"" and (tier == ReelFace.ResultTier.SUCCESS or tier == ReelFace.ResultTier.CRIT_SUCCESS):
				face.rider_effect_id = rider_id
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel

## Upgrades every face on this reel to a guaranteed CRIT_SUCCESS (multiplier 2.0), unconditionally
## — used by "guaranteed crit on this reel" talents (Ranger Focused Trap on Snare Trap, Ranger Point
## Blank on Collateral Damage). Deliberately upgrades ALL tiers, not just SUCCESS: whenever the
## defender is already Marked (both talents require this as their own precondition), Combatant.
## hunters_mark_reels() runs later in the spin and rebuilds CRIT_FAILURE/FAILURE faces back into
## plain SUCCESS — upgrading only SUCCESS faces here would leave some of those rebuilt faces as
## non-crit hits, breaking the "guaranteed critical" promise.
func force_guaranteed_crit() -> void:
	for f: ReelFace in faces:
		f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
		f.multiplier = 2.0

## Chancer "Double or Nothing" (L9) wild gambler's reel (playtest 2026-07-04, player-specified exact
## distribution): a genuine ALL-OR-NOTHING reel — no FAILURE or NEUTRAL faces at all. Scaled 5x
## (2026-08-13 accuracy-stat spec §2) to a 100-face strip (not 20) for consistency with every other
## reel variant's new face-count granularity, same percentages: 25 crit-failure (25%), 10 success
## (10%), 65 crit-success (65%). Used for BOTH the caster's existing weapon-attack reels (via
## Combatant.gambled_reels()) and the ability's own 2 bonus reels — a whole-spin effect, not a
## partial one, matching the ability's original "wild crit-biased" framing.
const GAMBLE_COMPOSITION := [
	[ReelFace.ResultTier.CRIT_FAILURE, 0.0, 25],
	[ReelFace.ResultTier.SUCCESS, 1.0, 10],
	[ReelFace.ResultTier.CRIT_SUCCESS, 2.0, 65],
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

## Builds the Warden's "Rallying Cry" reel (spec 2026-06-29 §3): a no-damage UTILITY reel, scaled 5x
## (2026-08-13 accuracy-stat spec §2) to 10 crit-success + 40 success faces (no fail/neutral/crit-
## fail). Every face deals zero direct damage (multiplier 0) and carries NO rider — the orchestrator
## reads the landed tier post-spin and shields the party (SUCCESS → half-weapon, CRIT_SUCCESS →
## full-weapon). is_weapon_attack = false → it stays OUT of paylines, is never WILD-biased, and sits
## at the loadout tail.
static func make_rallying_cry(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.is_weapon_attack = false
	reel.charges_meter = false  # the shield IS the payoff — don't also feed the Bonus Meter (playtest 2026-06-29)
	for i: int in range(10):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(40):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()  # balance-neutral: only adjacency varies, tier counts fixed
	return reel

## Builds the item-use reel (2026-07-16 combat item-use targeting design §2): a no-damage utility
## reel with NO failure tiers at all — a potion should never simply fail. Scaled 5x (2026-08-13
## accuracy-stat spec §2) to 45 SUCCESS + 5 CRIT_SUCCESS (90%/10%). Every face has multiplier 0; the
## orchestrator reads the landed tier post-spin and applies the item's real effect (e.g. a heal,
## ×1.5 on crit) itself, same convention as make_rallying_cry(). is_weapon_attack = false (out of
## paylines); charges_meter = false (the item's effect IS the payoff — same reasoning already used
## for Rallying Cry).
static func make_item_use(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.is_weapon_attack = false
	reel.charges_meter = false
	for i: int in range(5):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(45):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()
	return reel

## Builds the minion-summon reel (2026-08-16 minion-summoning-class spec §3): a no-damage utility
## reel with NO failure tiers — identical shape to make_item_use() (45 SUCCESS + 5 CRIT_SUCCESS,
## 90%/10%), since a summon should never simply fail, only land baseline vs. a stronger/tankier
## variant. Every face has multiplier 0; the orchestrator reads the landed tier post-spin and
## builds the minion itself (SUCCESS = baseline, CRIT_SUCCESS = the tankier variant).
## is_weapon_attack = false (out of paylines); charges_meter = false (same reasoning as
## make_rallying_cry()/make_item_use() — the summon IS the payoff).
static func make_summon_reel() -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.is_weapon_attack = false
	reel.charges_meter = false
	for i: int in range(5):
		reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(45):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()
	return reel

## Builds the Flee-attempt reel (2026-08-16 combat-encounter-revamp spec §1): a no-damage
## utility reel reusing ABILITY_COMPOSITION's tier counts/odds (5 crit-fail / 10 fail / 30
## success / 5 crit-success, out of 50) — same shape already approved for resource-costed
## abilities, no new numbers invented. Every face has multiplier 0 (Flee never deals damage)
## and no rider. is_weapon_attack = false (out of paylines, same convention as Rallying Cry/
## item-use); charges_meter = false (attempting to escape shouldn't fuel the Bonus Meter).
## The orchestrator reads the landed tier post-spin: SUCCESS/CRIT_SUCCESS ends the encounter,
## FAILURE/CRIT_FAILURE just wastes the turn. [ASSUMPTION] tune tier weights by playtest,
## same as every other reel composition.
static func make_flee() -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = null
	reel.is_weapon_attack = false
	reel.charges_meter = false
	for entry: Array in ABILITY_COMPOSITION:
		var tier: ReelFace.ResultTier = entry[0]
		var count: int = entry[2]
		for i: int in range(count):
			reel.faces.append(_make_face(tier, 0.0))
	reel.faces.shuffle()
	return reel

static func _make_face(tier: ReelFace.ResultTier, multiplier: float) -> ReelFace:
	var face: ReelFace = ReelFace.new()
	face.result_tier = tier
	face.multiplier = multiplier
	return face
