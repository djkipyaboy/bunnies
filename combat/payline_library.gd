class_name PaylineLibrary
extends RefCounted

## Generates the payline set for a 3-row × [param width] grid (DESIGN spec 2026-06-20). A line is an
## Array[Vector2i] of (col,row) cells (row 0=top, 1=center, 2=bottom). Three families:
##   • columns  — one per reel, the 3 cells of that column        (length 3)
##   • rows     — one per row, all `width` cells                  (length = width)
##   • diagonals— length-3 segments over 3 adjacent columns, both ways (none when width < 3)
## Returned as a flat Array of lines so a future Luck build can append extra lines.

const ROWS: int = 3

static func lines_for(width: int) -> Array:
	var lines: Array = []
	for c: int in range(width):  # columns
		lines.append([Vector2i(c, 0), Vector2i(c, 1), Vector2i(c, 2)])
	for r: int in range(ROWS):  # rows
		var row_line: Array = []
		for c: int in range(width):
			row_line.append(Vector2i(c, r))
		lines.append(row_line)
	for s: int in range(width - 2):  # diagonals (length 3), both directions
		lines.append([Vector2i(s, 0), Vector2i(s + 1, 1), Vector2i(s + 2, 2)])
		lines.append([Vector2i(s, 2), Vector2i(s + 1, 1), Vector2i(s + 2, 0)])
	return lines
