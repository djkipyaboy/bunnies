extends SceneTree

# Headless test: TeamUpMinigame's pure grid/lock/spin/tally logic (2026-07-29 spec §4, §9). No
# scene/UI involved. tally() needs TeamUpPaylineResolver (Task 3) — the surge-payline assertions
# near the bottom of _initialize() will fail until Task 3 lands; everything above them is
# independently correct once Task 2 alone is done.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_minigame.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _uniform_reel(symbol: StringName) -> TeamUpReel:
	return TeamUpReel.make_default([[symbol, 1]])

func _initialize() -> void:
	# --- Construction ---
	var reels: Array[TeamUpReel] = [_uniform_reel(&"strike"), _uniform_reel(&"mend")]
	var mg: TeamUpMinigame = TeamUpMinigame.new(reels, 9, 5)
	_check(mg.lock_tokens_remaining == 9, "lock_tokens_remaining starts at the constructor value")
	_check(mg.spins_remaining == 5, "spins_remaining starts at the constructor value")
	_check(mg.grid.size() == 2, "grid has one column per reel (got %d)" % mg.grid.size())
	_check(mg.grid[0].size() == 3, "each column has 3 rows (got %d)" % mg.grid[0].size())
	_check(mg.grid[0][0] == null, "the grid starts empty before any spin")
	_check(not mg.is_complete(), "not complete before any spin")

	# --- spin() fills every position and consumes a spin ---
	_check(mg.spin(), "spin() succeeds while spins remain")
	_check(mg.spins_remaining == 4, "spin() decrements spins_remaining (got %d)" % mg.spins_remaining)
	_check(mg.grid[0][0] != null and mg.grid[0][1] != null and mg.grid[0][2] != null, "every row of column 0 is filled after a spin")
	_check(mg.grid[0][0].team_up_symbol == &"strike", "column 0 draws from its own reel's symbol (uniform reel -> always strike)")
	_check(mg.grid[1][0].team_up_symbol == &"mend", "column 1 draws from its own reel's symbol")

	# --- lock() freezes a position deterministically (identity check, not a probabilistic "changed") ---
	var locked_face: ReelFace = mg.grid[0][0]
	_check(mg.lock(0, 0), "lock() succeeds on a visible, unlocked position")
	_check(mg.locked[0][0], "locked[col][row] flips true")
	_check(mg.lock_tokens_remaining == 8, "lock() consumes one token (got %d)" % mg.lock_tokens_remaining)
	mg.spin()
	_check(mg.grid[0][0] == locked_face, "a locked position's face is the SAME object across a subsequent spin (never redrawn)")
	mg.spin()
	_check(mg.grid[0][0] == locked_face, "...and stays the same object across a second subsequent spin")
	_check(not mg.lock(0, 0), "re-locking an already-locked position is a no-op (returns false, no extra token spent)")
	_check(mg.lock_tokens_remaining == 8, "the no-op re-lock didn't consume another token")

	# --- Unlocked rows within the SAME column genuinely redraw independently (spec §9: "confirm
	# the 3 row positions per reel are drawn independently, not sharing one landed index the way
	# ActionReel's grid does"). Proven operationally rather than by reading _select_index() calls: a
	# 5-distinct-symbol reel, one row locked, the other two rows re-spun ~19 more times — if rows
	# were coupled via one shared landed index (like CombatResolver._build_grid()'s posmod
	# adjacency), the locked row freezing would say nothing about the others; independence means the
	# OTHER rows can and do keep changing while the locked one provably doesn't. Chance of a truly
	# independent 5-symbol row showing only 1 distinct value across 19 draws is (1/5)^18 — not a
	# real flake risk.
	var varied_reel: TeamUpReel = TeamUpReel.make_default([[&"strike", 1], [&"mend", 1], [&"ward", 1], [&"break", 1], [&"surge", 1]])
	var mg_indep: TeamUpMinigame = TeamUpMinigame.new([varied_reel], 9, 20)
	mg_indep.spin()
	var row0_locked_face: ReelFace = mg_indep.grid[0][0]
	_check(mg_indep.lock(0, 0), "lock row 0 of the only column")
	var row1_symbols_seen: Dictionary = {}
	var row2_symbols_seen: Dictionary = {}
	for i: int in range(19):
		mg_indep.spin()
		_check(mg_indep.grid[0][0] == row0_locked_face, "locked row 0 stays fixed across spin %d" % (i + 1))
		row1_symbols_seen[mg_indep.grid[0][1].team_up_symbol] = true
		row2_symbols_seen[mg_indep.grid[0][2].team_up_symbol] = true
	_check(row1_symbols_seen.size() > 1, "unlocked row 1 (same column as the locked row 0) shows more than one distinct symbol across 19 re-spins — it is NOT frozen alongside row 0")
	_check(row2_symbols_seen.size() > 1, "unlocked row 2 independently varies too — rows 1 and 2 are not coupled to each other or to row 0")

	# --- lock() runs out of tokens ---
	var mg2: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike"), _uniform_reel(&"mend")], 1, 5)
	mg2.spin()
	_check(mg2.lock(0, 0), "the first lock succeeds (1 token available)")
	_check(not mg2.lock(0, 1), "a second lock fails once tokens are exhausted (returns false)")
	_check(not mg2.locked[0][1], "the failed lock attempt left that position unlocked")

	# --- lock() rejects out-of-bounds / empty positions ---
	var mg3: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike")], 9, 5)
	_check(not mg3.lock(0, 0), "lock() fails on an empty (never-spun) position")
	_check(not mg3.lock(5, 0), "lock() fails on an out-of-bounds column")
	_check(not mg3.lock(0, 9), "lock() fails on an out-of-bounds row")

	# --- is_complete() / spin() exhaustion ---
	var mg4: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike")], 9, 2)
	mg4.spin()
	_check(not mg4.is_complete(), "not complete after 1 of 2 spins")
	mg4.spin()
	_check(mg4.is_complete(), "complete after using all spins")
	var grid_snapshot: ReelFace = mg4.grid[0][0]
	_check(not mg4.spin(), "spin() returns false once complete")
	_check(mg4.grid[0][0] == grid_snapshot, "an over-called spin() leaves the grid untouched")

	# --- tally(): symbol counts + surge-line detection (needs TeamUpPaylineResolver, Task 3) ---
	var mg5: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"strike"), _uniform_reel(&"strike")], 9, 1)
	mg5.spin()
	var t5: Dictionary = mg5.tally()
	_check(t5["strike"] == 6, "a fully-strike 2x3 grid tallies 6 strike (got %d)" % t5["strike"])
	_check(t5["mend"] == 0 and t5["ward"] == 0 and t5["break"] == 0, "other symbol counts are 0")
	_check(t5["surge_lines"] == 0, "no surge symbols anywhere -> 0 completed surge lines")

	var mg6: TeamUpMinigame = TeamUpMinigame.new([_uniform_reel(&"surge"), _uniform_reel(&"surge")], 9, 1)
	mg6.spin()
	var t6: Dictionary = mg6.tally()
	# PaylineLibrary.lines_for(2): 2 columns (length 3) + 3 rows (length 2) + 0 diagonals (width<3) = 5 lines.
	# Every cell is "surge", so all 5 lines complete.
	_check(t6["surge_lines"] == 5, "a fully-surge 2x3 grid completes all 5 of PaylineLibrary.lines_for(2)'s lines (got %d)" % t6["surge_lines"])

	print(("TEAM UP MINIGAME TEST PASSED" if _failures == 0 else "TEAM UP MINIGAME TEST FAILED: %d" % _failures))
	quit(_failures)
