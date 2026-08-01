extends SceneTree

## Headless test: TeamUpMinigame.end_early() lets the player bank the current grid instead of
## burning every remaining spin. Disabled (can_end_early() == false) before the first spin and
## once the round is already complete. Player request, 2026-08-01 playtest follow-up.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_end_early.gd

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var reel: TeamUpReel = TeamUpReel.new()
	var face: ReelFace = ReelFace.new()
	face.team_up_symbol = &"strike"
	reel.faces = [face]
	var reels: Array[TeamUpReel] = [reel, reel, reel]
	var game: TeamUpMinigame = TeamUpMinigame.new(reels, 3, 5)

	_check(not game.can_end_early(), "can't end early before any spin has happened")
	game.end_early()
	_check(not game.is_complete(), "end_early() before any spin is a safe no-op (spins_remaining was already 0-relative, nothing to bank)")

	var game2: TeamUpMinigame = TeamUpMinigame.new(reels, 3, 5)
	game2.spin()
	_check(game2.can_end_early(), "can end early once at least one spin has happened")
	_check(not game2.is_complete(), "round isn't complete yet (1 of 5 spins used, still mid-round)")

	game2.end_early()
	_check(game2.is_complete(), "end_early() completes the round")
	_check(game2.spins_remaining == 0, "end_early() zeroes spins_remaining (got %d)" % game2.spins_remaining)
	var tally: Dictionary = game2.tally()
	_check(tally.get("strike", 0) > 0, "tally() reflects whatever was on the grid when banked (got %d strike)" % tally.get("strike", 0))

	_check(not game2.can_end_early(), "can't end early again once the round is already complete")

	print(("TEAM UP MINIGAME END EARLY TEST PASSED" if _failures == 0 else "TEAM UP MINIGAME END EARLY TEST FAILED: %d" % _failures))
	quit(_failures)
