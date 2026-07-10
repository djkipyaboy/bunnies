extends SceneTree

# Headless test: Might converts to reel-count-normalized flat damage (WoW AP-normalized-by-speed
# analog, reel-count instead of weapon speed).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_might_scaling.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	var s: Stats = Stats.new(); s.might = 3   # power = 3 * 2.0 = 6.0
	c.base_stats = s

	# 2-reel "heavy" loadout: 6.0 / 2 = 3 per reel.
	_check(c.might_damage_bonus_per_reel(2) == 3, "2 reels -> 3 dmg/reel (got %d)" % c.might_damage_bonus_per_reel(2))
	# 3-reel "typical" loadout: ceil(6.0 / 3) = 2 per reel.
	_check(c.might_damage_bonus_per_reel(3) == 2, "3 reels -> 2 dmg/reel (got %d)" % c.might_damage_bonus_per_reel(3))
	# 5-reel "rapid" loadout: ceil(6.0 / 5) = 2 per reel (smaller share, but more procs).
	_check(c.might_damage_bonus_per_reel(5) == 2, "5 reels -> 2 dmg/reel (got %d)" % c.might_damage_bonus_per_reel(5))

	# 0 Might -> 0 bonus regardless of reel count.
	var zero: Combatant = Combatant.new()
	_check(zero.might_damage_bonus_per_reel(3) == 0, "0 Might -> 0 bonus")

	print(("MIGHT SCALING TEST PASSED" if _failures == 0 else "MIGHT SCALING TEST FAILED: %d" % _failures))
	quit(_failures)
