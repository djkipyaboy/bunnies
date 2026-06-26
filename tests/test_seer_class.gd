extends SceneTree

# Headless: the Seer class builds with the right profile (Mystic, 2 reels, mana-only 15/15, Luck 0,
# select_fate/big_bang ids). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_seer_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(&"seer" in ClassLibrary.IDS, "seer is in the roster IDS")
	var cls: CharacterClass = ClassLibrary.make(&"seer")
	_check(cls != null, "make(seer) returns a class")
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	_check(cls.weapon_type == mystic, "weapon type is Mystic")
	_check(cls.defense_type == mystic, "defends as Mystic")
	_check(cls.reel_count == 2, "2 reels (got %d)" % cls.reel_count)
	_check(cls.base_stats.luck == 0, "Luck 0 — Luck is Chancer-exclusive (got %d)" % cls.base_stats.luck)
	_check(cls.base_stats.focus == 6, "Focus 6 (got %d)" % cls.base_stats.focus)
	_check(cls.ability_id == &"select_fate", "ability is select_fate")
	_check(cls.ability_cost == 6 and cls.ability_resource == &"mana", "select_fate costs 6 mana")
	_check(cls.ultimate_id == &"big_bang", "ultimate is big_bang")
	_check(cls.base_max_stamina == 0, "mana-only: base_max_stamina 0 (got %d)" % cls.base_max_stamina)

	# Built combatant: mana-only 15/15 (9 base + 6 Focus), 2 weapon reels, no Luck crit faces added.
	var c: Combatant = cls.build_combatant(true)
	_check(c.resource_pool.max_mana == 15, "total mana 15 (9 base + 6 Focus, got %d)" % c.resource_pool.max_mana)
	_check(c.resource_pool.mana == 15, "starts full on mana (got %d)" % c.resource_pool.mana)
	_check(c.resource_pool.max_stamina == 0, "no stamina rail (got %d)" % c.resource_pool.max_stamina)
	_check(c.weapon.reels.size() == 2, "2 weapon reels (got %d)" % c.weapon.reels.size())
	var crit: int = 0
	for f: ReelFace in c.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
	_check(crit == 1, "Luck 0 → default single crit face (got %d)" % crit)

	print(("SEER CLASS TEST PASSED" if _failures == 0 else "SEER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
