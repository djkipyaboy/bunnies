class_name CombatResolver
extends Node

## Resolves one character's Combat Phase: spins a set of [ActionReel]s and applies EACH as an
## INDEPENDENT attack (DESIGN.md §4.5, §10 Decision 1). Replaces the old casino SlotMachine —
## there is no grid, no paylines, no payout/credits. Output is damage + Bonus-Meter charge.
##
## Self-contained on purpose: it takes the reels and a base damage value and reports results via
## signals. The full turn structure ([code]PhaseManager[/code]) and combatant state
## ([code]Combatant[/code], [code]BonusMeter[/code]) are layered on later — see DESIGN.md §8.

# ---------------------------------------------------------------------------
# Result type  (declared before the signals that reference it)
# ---------------------------------------------------------------------------

## The independent outcome of a single Action reel within a Combat Phase.
class AttackResult:
	var face: ReelFace                       ## The landed face.
	var damage_type: DamageType              ## Type the attack dealt (may be null in tests).
	var base_damage: float = 0.0             ## Weapon base damage fed in.
	var final_damage: int = 0                ## After multiplier + type chart, rounded.
	var meter_gain: int = 0                  ## Bonus-Meter charge this face contributed.
	var rider_effect_id: StringName = &""    ## Rider to apply (crit-success of a riding type); empty = none.
	var landed_index: int = -1               ## Strip index the reel landed on (for grid + strip sync).

# ---------------------------------------------------------------------------
# Signals  (naming convention: snake_case, past-tense — CLAUDE.md §2)
# ---------------------------------------------------------------------------

## Emitted at the start of the Combat Phase spin, before any reel resolves.
signal spin_started

## Emitted once for each reel's independent attack, in spin order.
signal damage_applied(attack: AttackResult)

## Emitted with the total Bonus-Meter charge accrued from this spin's faces.
signal meter_charged(amount: int)

## Emitted once the whole phase resolves. [param attacks] holds every [AttackResult], in order.
signal spin_resolved(attacks: Array[AttackResult])

## The most recent spin's weapon grid: Array[col] of Array[row]=ReelFace (3 rows). For UI + paylines.
var last_grid: Array = []

## Emitted after [signal spin_resolved] with the scoring payline hits (Array of PaylineResolver.PaylineHit).
signal paylines_resolved(hits: Array)

# ---------------------------------------------------------------------------
# Tuning data  ([ASSUMPTION] placeholders — tune by playtest, DESIGN.md §4.9)
# ---------------------------------------------------------------------------

## Bonus-Meter charge per result tier, indexed by [enum ReelFace.ResultTier].
## First pass: crit-fail 0, fail 0, neutral +1, success +2, crit-success +3.
@export var meter_charge_weights: Array[int] = [0, 0, 1, 2, 3]

## Probability that a Sticky-Wild reel lands its crit face (a BIAS, not a force). The other
## ~35% is a normal weighted spin, so wild grids vary (more payline variety). [ASSUMPTION]
const WILD_CRIT_CHANCE: float = 0.65  # [ASSUMPTION]

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Spins every reel in [param reels] independently against a [param target_type] defender,
## using [param base_damage] as the weapon base. Returns the per-reel [AttackResult]s and emits
## [signal spin_started] → [signal damage_applied] (per reel) → [signal meter_charged] →
## [signal spin_resolved].
func resolve_combat_phase(reels: Array[ActionReel], base_damage: float, target_type: DamageType = null, wild_reel_indices: Array[int] = [], weapon_reel_count: int = -1, flat_damage_bonus: int = 0, extra_lines: Array = []) -> Array[AttackResult]:
	spin_started.emit()

	var attacks: Array[AttackResult] = []
	var total_meter: int = 0

	for i: int in range(reels.size()):
		var is_wild: bool = i in wild_reel_indices
		var attack: AttackResult = _resolve_single(reels[i], base_damage, target_type, is_wild, flat_damage_bonus)
		total_meter += attack.meter_gain
		attacks.append(attack)
		damage_applied.emit(attack)

	meter_charged.emit(total_meter)
	spin_resolved.emit(attacks)

	# Build the weapon grid (first weapon_reel_count reels; -1 = all) and evaluate paylines.
	var wcount: int = weapon_reel_count if weapon_reel_count >= 0 else reels.size()
	wcount = mini(wcount, reels.size())
	last_grid = _build_grid(reels, attacks, wcount)
	var lines: Array = PaylineLibrary.lines_for(wcount)
	lines.append_array(extra_lines)
	paylines_resolved.emit(PaylineResolver.evaluate(last_grid, lines))
	return attacks

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Resolves one reel into an [AttackResult]: spin → damage (multiplier × type chart) → meter.
func _resolve_single(reel: ActionReel, base_damage: float, target_type: DamageType, is_wild: bool = false, flat_damage_bonus: int = 0) -> AttackResult:
	var face: ReelFace
	var index: int
	if is_wild and randf() < WILD_CRIT_CHANCE:
		# Biased toward crit (not forced): land the crit face this spin.
		face = _crit_face(reel)
		index = reel.faces.find(face)
	else:
		# Normal weighted spin — both for non-wild reels and the ~35% non-crit wild case.
		face = reel.spin()
		index = reel.get_last_index()

	var attack: AttackResult = AttackResult.new()
	attack.face = face
	attack.damage_type = reel.damage_type
	attack.base_damage = base_damage
	attack.landed_index = index

	if face != null:
		# Neutral and the failure tiers deal no weapon damage (their value is utility + meter).
		# A HIT face with multiplier 0 (the Warrior's Rend reel) also deals no direct damage — its
		# value is the rider it carries. Flat Might is added only to faces that deal weapon damage.
		if face.deals_damage() and face.multiplier > 0.0:
			var raw: float = base_damage * face.multiplier
			var type_mult: float = reel.damage_type.multiplier_against(target_type) if reel.damage_type != null else 1.0
			attack.final_damage = ceili(raw * type_mult) + flat_damage_bonus  # round UP (project convention)
		attack.meter_gain = _meter_gain_for(face.result_tier)
		# Crit-success of a type that carries an inherent rider (Crushing -> Slow) reports it.
		# The resolver only REPORTS; the orchestrator attaches the Effect (ARCHITECTURE §2).
		if face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and reel.damage_type != null and reel.damage_type.inherent_rider_id != &"":
			attack.rider_effect_id = reel.damage_type.inherent_rider_id
		# Per-face rider (e.g. the Rend reel's &"bleed") reports on any HIT tier — orchestrator applies
		# it. Takes precedence over the type's inherent rider when both are present.
		if face.rider_effect_id != &"" and (face.result_tier == ReelFace.ResultTier.SUCCESS or face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS):
			attack.rider_effect_id = face.rider_effect_id

	return attack

## Looks up the Bonus-Meter charge for a result tier, guarding the weights array length.
func _meter_gain_for(tier: ReelFace.ResultTier) -> int:
	if tier >= 0 and tier < meter_charge_weights.size():
		return meter_charge_weights[tier]
	return 0

## Returns the reel's first crit-success face (the Sticky-Wild target). Falls back to a normal
## spin if the reel has no crit-success face, so a wild never crashes on an odd strip.
func _crit_face(reel: ActionReel) -> ReelFace:
	for face: ReelFace in reel.faces:
		if face != null and face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			return face
	return reel.spin()

## Builds the 3-row x wcount-col grid from the weapon reels' landed windows (top/center/bottom,
## wrapping the strip). grid[col] = [top, center, bottom] ReelFaces.
func _build_grid(reels: Array[ActionReel], attacks: Array[AttackResult], wcount: int) -> Array:
	var grid: Array = []
	for c: int in range(wcount):
		var reel: ActionReel = reels[c]
		var n: int = reel.faces.size()
		if n == 0:
			grid.append([null, null, null])
			continue
		var idx: int = attacks[c].landed_index
		var top: ReelFace = reel.faces[posmod(idx - 1, n)]
		var center: ReelFace = reel.faces[posmod(idx, n)]
		var bottom: ReelFace = reel.faces[posmod(idx + 1, n)]
		grid.append([top, center, bottom])
	return grid
