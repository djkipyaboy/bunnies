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

## The Chancer's casino payline set: curated left-to-right paths (one cell per reel, col 0 → width-1),
## scored left-aligned (see PaylineResolver.evaluate_left_align). For width 4 (the Chancer) a hand-picked
## set of 20 distinct zigzag/straight rows. Other widths fall back to lines_for (Chancer is always 4).
static func casino_lines(width: int) -> Array:
	if width != 4:
		return lines_for(width)
	# Row sequence per line (row 0=top, 1=center, 2=bottom), one row per reel. Adjacency kept within
	# one row for clean readable zigzags. 20 distinct paths.
	var patterns: Array = [
		[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2],
		[0, 1, 2, 2], [2, 1, 0, 0], [0, 0, 1, 2], [2, 2, 1, 0],
		[1, 0, 0, 1], [1, 2, 2, 1], [0, 1, 1, 0], [2, 1, 1, 2],
		[1, 0, 1, 0], [1, 2, 1, 2], [0, 1, 0, 1], [2, 1, 2, 1],
		[1, 1, 0, 0], [1, 1, 2, 2], [0, 0, 1, 1], [2, 2, 1, 1], [1, 0, 1, 2],
	]
	var lines: Array = []
	for pat: Array in patterns:
		var line: Array = []
		for c: int in range(pat.size()):
			line.append(Vector2i(c, pat[c]))
		lines.append(line)
	return lines

## Returns the line set for a payline profile id (Combatant.payline_profile_id).
static func lines_for_profile(profile_id: StringName, width: int) -> Array:
	if profile_id == &"casino":
		return casino_lines(width)
	return lines_for(width)
