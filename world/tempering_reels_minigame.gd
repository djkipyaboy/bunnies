class_name TemperingReelsMinigame
extends RefCounted

## Pure model for Salvaging's opt-in "Tempering Reels" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.1) -- N+1 continuously-rotating BonusReels, stopped manually by the
## player (Fishing's exact advance()/stop()/current_face()/all_stopped() mechanic, reused as-is).
## N = RecipeLibrary.stat_slot_count_for_rarity(rarity). Reels 1..N each roll a >= 0 delta for the
## slot's already-fixed primary/secondary stat; the final reel always adds something (amplifies one
## of them, or unlocks a small tertiary stat). resolve() is therefore always a delta that only ever
## ADDS on top of the recipe's deterministic base -- skipping this mini-game entirely is equivalent
## to every reel landing on its zero face, so opting in is never worse.

const STAT_FACE_STEPS: Array[int] = [0, 1, 1, 2]   # 4 faces per stat-slot reel, worst face is +0
const TEMPER_AMPLIFY_MAGNITUDE: int = 2
const TEMPER_TERTIARY_MAGNITUDE: int = 1
const SECONDS_PER_TICK: float = 0.15

var reels: Array[BonusReel] = []
var primary_stat: StringName
var secondary_stat: StringName
var tertiary_stat: StringName
var _stat_count: int
var _current_indices: Array[int] = []
var _stopped: Array[bool] = []
var _elapsed: Array[float] = []

func _init(p_primary_stat: StringName, p_secondary_stat: StringName, p_tertiary_stat: StringName, stat_count: int) -> void:
	primary_stat = p_primary_stat
	secondary_stat = p_secondary_stat
	tertiary_stat = p_tertiary_stat
	_stat_count = stat_count
	reels.append(_make_stat_reel())
	if stat_count >= 2:
		reels.append(_make_stat_reel())
	reels.append(_make_temper_reel())
	for i in range(reels.size()):
		_current_indices.append(0)
		_stopped.append(false)
		_elapsed.append(0.0)

static func _make_stat_reel() -> BonusReel:
	var composition: Array = []
	for step: int in STAT_FACE_STEPS:
		composition.append([&"stat_value", step, 1])
	return BonusReel.make_default(composition)

static func _make_temper_reel() -> BonusReel:
	return BonusReel.make_default([
		[&"amplify_primary", TEMPER_AMPLIFY_MAGNITUDE, 2],
		[&"amplify_secondary", TEMPER_AMPLIFY_MAGNITUDE, 2],
		[&"bonus_tertiary", TEMPER_TERTIARY_MAGNITUDE, 2],
	])

func advance(delta: float) -> void:
	for i in range(reels.size()):
		if _stopped[i]:
			continue
		_elapsed[i] += delta
		while _elapsed[i] >= SECONDS_PER_TICK:
			_elapsed[i] -= SECONDS_PER_TICK
			_current_indices[i] = (_current_indices[i] + 1) % reels[i].faces.size()

func current_face(col: int) -> ReelFace:
	return reels[col].faces[_current_indices[col]]

func face_at(col: int, offset: int) -> ReelFace:
	var size: int = reels[col].faces.size()
	var index: int = ((_current_indices[col] + offset) % size + size) % size
	return reels[col].faces[index]

func is_stopped(col: int) -> bool:
	return _stopped[col]

func stop(col: int) -> ReelFace:
	_stopped[col] = true
	return current_face(col)

func all_stopped() -> bool:
	return not _stopped.has(false)

## Resolves every stopped reel into a Stats DELTA to add (via Stats.plus()) on top of the recipe's
## deterministic base -- meaningless before all_stopped().
func resolve() -> Stats:
	var result: Stats = Stats.new()
	_add_to_stat(result, primary_stat, int(current_face(0).bonus_magnitude))
	if _stat_count >= 2:
		_add_to_stat(result, secondary_stat, int(current_face(1).bonus_magnitude))
	var temper_face: ReelFace = current_face(reels.size() - 1)
	match temper_face.bonus_mode:
		&"amplify_primary":
			_add_to_stat(result, primary_stat, int(temper_face.bonus_magnitude))
		&"amplify_secondary":
			var target: StringName = secondary_stat if _stat_count >= 2 else primary_stat
			_add_to_stat(result, target, int(temper_face.bonus_magnitude))
		&"bonus_tertiary":
			_add_to_stat(result, tertiary_stat, int(temper_face.bonus_magnitude))
	return result

static func _add_to_stat(stats: Stats, stat_name: StringName, amount: int) -> void:
	match stat_name:
		&"might": stats.might += amount
		&"finesse": stats.finesse += amount
		&"vigor": stats.vigor += amount
		&"focus": stats.focus += amount
		&"grit": stats.grit += amount
		&"luck": stats.luck += amount
