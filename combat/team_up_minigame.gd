class_name TeamUpMinigame
extends RefCounted

## Pure model for the Team-Up! bonus round (2026-07-29 spec §4): a reels.size()-column x 3-row
## grid, independently-drawn per position, with Hold & Win token-budgeted locking across a fixed
## number of spins. TeamUpPanel is the view; this class holds no Node/UI state and is fully
## headless-testable, mirroring this project's resolver/orchestrator split.

const ROWS: int = 3

var reels: Array[TeamUpReel] = []
var grid: Array = []          # grid[col][row] = ReelFace
var locked: Array = []        # locked[col][row] = bool
var lock_tokens_remaining: int
var spins_remaining: int
var _cols: int
## Cells locked since the last spin() call — only these can be unlock()'d (player request,
## 2026-08-01): a lock committed by an EARLIER spin is permanently held (the Hold & Win point).
var _locked_this_round: Array[Vector2i] = []

func _init(p_reels: Array[TeamUpReel], p_lock_tokens: int, p_max_spins: int) -> void:
	reels = p_reels
	_cols = reels.size()
	lock_tokens_remaining = p_lock_tokens
	spins_remaining = p_max_spins
	for c: int in range(_cols):
		grid.append([null, null, null])
		locked.append([false, false, false])

## Draws a fresh face for every UNLOCKED position (locked positions keep their current face
## object). Consumes one spin. No-op (returns false, grid untouched) once spins_remaining is 0.
func spin() -> bool:
	if spins_remaining <= 0:
		return false
	for c: int in range(_cols):
		for r: int in range(ROWS):
			if not locked[c][r]:
				grid[c][r] = reels[c].spin()
	spins_remaining -= 1
	_locked_this_round.clear()
	return true

## Locks a currently-visible position, freezing it for all remaining spins. Spending a token is
## always optional (spec §4) — this only ever gets CALLED when the player chooses to. Returns
## false (no-op, no token spent) if out of bounds, already locked, empty, or no tokens remain.
func lock(col: int, row: int) -> bool:
	if lock_tokens_remaining <= 0:
		return false
	if col < 0 or col >= _cols or row < 0 or row >= ROWS:
		return false
	if locked[col][row] or grid[col][row] == null:
		return false
	locked[col][row] = true
	lock_tokens_remaining -= 1
	_locked_this_round.append(Vector2i(col, row))
	return true

## True if (col, row) is locked AND was locked THIS round (since the last spin()) — the only
## locks unlock() will undo. Bounds-safe.
func can_unlock(col: int, row: int) -> bool:
	if col < 0 or col >= _cols or row < 0 or row >= ROWS:
		return false
	return locked[col][row] and _locked_this_round.has(Vector2i(col, row))

## Undoes a same-round lock, refunding its token. Returns false (no-op) if the cell isn't locked,
## is out of bounds, or was locked by an EARLIER spin (see can_unlock()).
func unlock(col: int, row: int) -> bool:
	if not can_unlock(col, row):
		return false
	locked[col][row] = false
	lock_tokens_remaining += 1
	_locked_this_round.erase(Vector2i(col, row))
	return true

## True once every spin has been used. Every symbol is positive-for-the-party (spec §5) — there is
## no win/lose condition here, only "has the round finished."
func is_complete() -> bool:
	return spins_remaining <= 0

## Symbol counts + completed Surge-payline count over the current grid (2026-07-29 spec §4/§5).
## Meaningful once is_complete() is true, but callable earlier if TeamUpPanel wants a live preview.
func tally() -> Dictionary:
	var counts: Dictionary = {}
	for c: int in range(_cols):
		for r: int in range(ROWS):
			var face: ReelFace = grid[c][r]
			if face == null or face.team_up_symbol == &"":
				continue
			counts[face.team_up_symbol] = counts.get(face.team_up_symbol, 0) + 1
	var lines: Array = PaylineLibrary.lines_for(_cols)
	var surge_hits: Array = TeamUpPaylineResolver.evaluate_by_symbol(grid, lines, &"surge")
	return {
		"strike": counts.get(&"strike", 0),
		"mend": counts.get(&"mend", 0),
		"ward": counts.get(&"ward", 0),
		"break": counts.get(&"break", 0),
		"surge_lines": surge_hits.size(),
	}
