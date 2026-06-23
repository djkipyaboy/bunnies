extends SceneTree

# Headless: the Chancer class builds with the right profile (Storm, 4 reels, Luck 4, reroll/gamble ids).
# Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_chancer_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(&"chancer" in ClassLibrary.IDS, "chancer is in the roster IDS")
	var cls: CharacterClass = ClassLibrary.make(&"chancer")
	_check(cls != null, "make(chancer) returns a class")
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	_check(cls.weapon_type == storm, "weapon type is Storm")
	_check(cls.reel_count == 4, "4 reels (got %d)" % cls.reel_count)
	_check(cls.base_stats.luck == 4, "Luck 4 (got %d)" % cls.base_stats.luck)
	_check(cls.ability_id == &"reroll", "ability is reroll")
	_check(cls.ability_cost == 4 and cls.ability_resource == &"stamina", "reroll costs 4 stamina")
	_check(cls.ultimate_id == &"wildcard_gamble", "ultimate is wildcard_gamble")

	# Built combatant: 7 total stamina (6 base + 1 Focus), 4 weapon reels, Luck added crit faces.
	var c: Combatant = cls.build_combatant(true)
	_check(c.resource_pool.max_stamina == 7, "total stamina 7 (got %d)" % c.resource_pool.max_stamina)
	_check(c.weapon.reels.size() == 4, "4 weapon reels (got %d)" % c.weapon.reels.size())
	# apply_luck appended 4 crit-success faces per reel beyond the default composition.
	var crit: int = 0
	for f: ReelFace in c.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
	_check(crit >= 4, "Luck added >=4 crit faces (got %d)" % crit)

	print(("CHANCER CLASS TEST PASSED" if _failures == 0 else "CHANCER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
