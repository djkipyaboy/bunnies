extends SceneTree

# Headless: the Ranger class builds with the right profile (Piercing, 4 reels, Luck 0, mark/collateral ids).
# Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ranger_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(&"ranger" in ClassLibrary.IDS, "ranger is in the roster IDS")
	var cls: CharacterClass = ClassLibrary.make(&"ranger")
	_check(cls != null, "make(ranger) returns a class")
	var piercing: DamageType = load("res://combat/resources/types/piercing.tres")
	_check(cls.weapon_type == piercing, "weapon type is Piercing")
	_check(cls.defense_type == piercing, "defends as Piercing")
	_check(cls.reel_count == 4, "4 reels (got %d)" % cls.reel_count)
	_check(cls.base_stats.luck == 0, "Luck 0 — Luck is Chancer-exclusive (got %d)" % cls.base_stats.luck)
	_check(cls.base_stats.finesse == 4, "Finesse 4 (got %d)" % cls.base_stats.finesse)
	_check(cls.ability_id == &"hunters_mark", "ability is hunters_mark")
	_check(cls.ability_cost == 3 and cls.ability_resource == &"stamina", "hunters_mark costs 3 stamina")
	_check(cls.ultimate_id == &"collateral", "ultimate is collateral")

	# Built combatant: 10 total stamina (8 base + 2 Focus), 4 weapon reels, no Luck crit faces added.
	var c: Combatant = cls.build_combatant(true)
	_check(c.resource_pool.max_stamina == 10, "total stamina 10 (got %d)" % c.resource_pool.max_stamina)
	_check(c.weapon.reels.size() == 4, "4 weapon reels (got %d)" % c.weapon.reels.size())
	var crit: int = 0
	for f: ReelFace in c.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
	_check(crit == 1, "Luck 0 → default single crit face (got %d)" % crit)

	print(("RANGER CLASS TEST PASSED" if _failures == 0 else "RANGER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
