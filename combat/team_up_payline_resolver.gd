class_name TeamUpPaylineResolver
extends RefCounted

## Symbol-matching sibling of PaylineResolver (which matches on ReelFace.result_tier) — this
## matches on ReelFace.team_up_symbol instead (2026-07-29 spec §4). Same PaylineHit-shaped return
## and _cell() grid-lookup convention as the original, so a reader already familiar with
## PaylineResolver.evaluate() recognizes this immediately.

## One scoring line for a specific symbol.
class SymbolHit:
	var cells: Array         ## Array[Vector2i] (col,row) on the line.
	var symbol: StringName = &""
	var length: int = 0

## [param grid]: Array[col] of Array[row]=ReelFace. [param lines]: from PaylineLibrary.lines_for().
## Returns every line whose cells are ALL [param symbol] — unlike PaylineResolver.evaluate() (which
## discovers whichever tier the line's first cell has), this checks one caller-specified symbol at
## a time, since TeamUpMinigame.tally() only ever needs Surge-line detection.
static func evaluate_by_symbol(grid: Array, lines: Array, symbol: StringName) -> Array:
	var hits: Array = []
	for line: Array in lines:
		var all_match: bool = true
		for cell: Vector2i in line:
			var face: ReelFace = _cell(grid, cell)
			if face == null or face.team_up_symbol != symbol:
				all_match = false
				break
		if all_match:
			var hit: SymbolHit = SymbolHit.new()
			hit.cells = line
			hit.symbol = symbol
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
