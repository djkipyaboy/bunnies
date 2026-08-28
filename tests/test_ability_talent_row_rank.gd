extends SceneTree

# Headless test: ability_talent_row_rank() (design spec 2026-08-28 §1.1) — automatic, level-gated,
# reuses ability_talent_row_unlock_level()'s existing thresholds for a second, independent purpose.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talent_row_rank.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()

	# Below every threshold: every row is rank 1.
	c.level = 4
	for row_id: StringName in [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]:
		_check(c.ability_talent_row_rank(row_id) == 1, "level 4, %s -> rank 1 (got %d)" % [row_id, c.ability_talent_row_rank(row_id)])

	# Level 5: ONLY base_ability ranks up — the others stay rank 1 until their own threshold.
	c.level = 5
	_check(c.ability_talent_row_rank(&"base_ability") == 2, "level 5, base_ability -> rank 2 (got %d)" % c.ability_talent_row_rank(&"base_ability"))
	_check(c.ability_talent_row_rank(&"ability_l2") == 1, "level 5, ability_l2 still rank 1 (got %d)" % c.ability_talent_row_rank(&"ability_l2"))

	# Level 8: base_ability/l2/l3/l4 are all rank 2; passive/ultimate still rank 1.
	c.level = 8
	for row_id: StringName in [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4"]:
		_check(c.ability_talent_row_rank(row_id) == 2, "level 8, %s -> rank 2 (got %d)" % [row_id, c.ability_talent_row_rank(row_id)])
	_check(c.ability_talent_row_rank(&"passive") == 1, "level 8, passive still rank 1 (got %d)" % c.ability_talent_row_rank(&"passive"))
	_check(c.ability_talent_row_rank(&"ultimate") == 1, "level 8, ultimate still rank 1 (got %d)" % c.ability_talent_row_rank(&"ultimate"))

	# Level 9: passive ranks up (amplified); Ultimate does not yet (flipped order, spec §1.1).
	c.level = 9
	_check(c.ability_talent_row_rank(&"passive") == 2, "level 9, passive -> rank 2 (got %d)" % c.ability_talent_row_rank(&"passive"))
	_check(c.ability_talent_row_rank(&"ultimate") == 1, "level 9, ultimate still rank 1 (got %d)" % c.ability_talent_row_rank(&"ultimate"))

	# Level 10: Ultimate ranks up too. Everything is rank 2.
	c.level = 10
	for row_id: StringName in [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]:
		_check(c.ability_talent_row_rank(row_id) == 2, "level 10, %s -> rank 2 (got %d)" % [row_id, c.ability_talent_row_rank(row_id)])

	# Rank-up is independent of talent picks: reaching level 5 doesn't touch pick_ability_talent state.
	_check(c.ability_talent_picks.is_empty(), "no talent picks were made just by leveling (got %d entries)" % c.ability_talent_picks.size())

	# Unrecognized row_id: ability_talent_row_unlock_level() returns -1 for it, which must NOT be
	# treated as "always unlocked" (level >= -1 is always true) — it should safely default to rank 1.
	c.level = 10
	_check(c.ability_talent_row_rank(&"not_a_real_row") == 1, "level 10, unrecognized row_id -> rank 1, not max rank (got %d)" % c.ability_talent_row_rank(&"not_a_real_row"))

	print(("ABILITY TALENT ROW RANK TEST PASSED" if _failures == 0 else "ABILITY TALENT ROW RANK TEST FAILED: %d" % _failures))
	quit(_failures)
