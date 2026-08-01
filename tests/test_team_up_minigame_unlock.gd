extends SceneTree

## Headless test: TeamUpMinigame.unlock() lets the player undo a lock made THIS spin (before the
## next spin() call), refunding its token — but a lock committed by an EARLIER spin stays
## permanently held (that's the Hold & Win point). Player request, 2026-08-01 playtest follow-up.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_team_up_minigame_unlock.gd

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

	game.spin()
	_check(game.lock(0, 0), "locks (0,0) on the first spin's grid")
	_check(game.lock_tokens_remaining == 2, "locking spent a token (got %d)" % game.lock_tokens_remaining)
	_check(game.can_unlock(0, 0), "a lock made THIS spin can be undone")

	_check(game.unlock(0, 0), "unlock succeeds on a same-spin lock")
	_check(not game.locked[0][0], "(0,0) is no longer locked")
	_check(game.lock_tokens_remaining == 3, "unlocking refunded the token (got %d)" % game.lock_tokens_remaining)
	_check(not game.unlock(0, 0), "unlocking an already-unlocked cell is a no-op (returns false)")

	# Re-lock, then advance a spin — the lock is now from an EARLIER spin and must stay committed.
	_check(game.lock(0, 0), "re-locks (0,0)")
	game.spin()
	_check(game.locked[0][0], "(0,0) is still locked after the next spin")
	_check(not game.can_unlock(0, 0), "a lock from an EARLIER spin can no longer be undone")
	_check(not game.unlock(0, 0), "unlock() refuses a committed (earlier-spin) lock")
	_check(game.locked[0][0], "(0,0) is STILL locked — the refused unlock changed nothing")
	_check(game.lock_tokens_remaining == 2, "no token was refunded by the refused unlock (got %d)" % game.lock_tokens_remaining)

	_check(not game.can_unlock(9, 9), "can_unlock is bounds-safe for an out-of-range cell")
	_check(not game.unlock(9, 9), "unlock is bounds-safe for an out-of-range cell")

	print(("TEAM UP MINIGAME UNLOCK TEST PASSED" if _failures == 0 else "TEAM UP MINIGAME UNLOCK TEST FAILED: %d" % _failures))
	quit(_failures)
