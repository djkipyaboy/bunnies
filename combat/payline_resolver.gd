class_name PaylineResolver
extends RefCounted

## Finds scoring payline hits over a spin grid (DESIGN spec 2026-06-20). Pure: given the grid and a
## line set (from PaylineLibrary), returns the lines whose cells all share one SCORING tier. Failure
## tiers never score (single default difficulty). The resolver REPORTS; the orchestrator APPLIES.

## One scoring line.
class PaylineHit:
	var cells: Array                  ## Array[Vector2i] (col,row) on the line.
	var tier: ReelFace.ResultTier = ReelFace.ResultTier.NEUTRAL
	var length: int = 0

## Tiers that can score a line (failure tiers excluded).
const SCORING_TIERS: Array = [
	ReelFace.ResultTier.NEUTRAL,
	ReelFace.ResultTier.SUCCESS,
	ReelFace.ResultTier.CRIT_SUCCESS,
]

## [param grid]: Array[col] of Array[row]=ReelFace (3 rows). [param lines]: from PaylineLibrary.
static func evaluate(grid: Array, lines: Array) -> Array:
	var hits: Array = []
	for line: Array in lines:
		var first: ReelFace = _cell(grid, line[0])
		if first == null or not (first.result_tier in SCORING_TIERS):
			continue
		var tier: ReelFace.ResultTier = first.result_tier
		var all_match: bool = true
		for cell: Vector2i in line:
			var face: ReelFace = _cell(grid, cell)
			if face == null or face.result_tier != tier:
				all_match = false
				break
		if all_match:
			var hit: PaylineHit = PaylineHit.new()
			hit.cells = line
			hit.tier = tier
			hit.length = line.size()
			hits.append(hit)
	return hits

static func _cell(grid: Array, cell: Vector2i) -> ReelFace:
	if cell.x < 0 or cell.x >= grid.size():
		return null
	var col: Array = grid[cell.x]
	if cell.y < 0 or cell.y >= col.size():
		return null
	return col[cell.y]
