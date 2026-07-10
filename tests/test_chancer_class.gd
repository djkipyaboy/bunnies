extends SceneTree

# Headless: the Chancer class builds with the right profile (Storm, 4 reels, Luck 1, reroll/gamble ids).
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
	_check(cls.base_stats.luck == 1, "Luck 1 (got %d)" % cls.base_stats.luck)
	_check(cls.ability_id == &"reroll", "ability is reroll")
	_check(cls.ability_cost == 4 and cls.ability_resource == &"mana", "reroll costs 4 mana")
	_check(cls.ultimate_id == &"wildcard_gamble", "ultimate is wildcard_gamble")

	# Built combatant: Mana rail (playtest 2026-07-04: Storm is magical, switched from Stamina),
	# 10 total mana (9 base + 1 Focus), 4 weapon reels, Luck added crit faces.
	var c: Combatant = cls.build_combatant(true)
	_check(c.resource_pool.max_stamina == 0, "no stamina rail (got %d)" % c.resource_pool.max_stamina)
	_check(c.resource_pool.max_mana == 10, "total mana 10 (got %d)" % c.resource_pool.max_mana)
	_check(c.weapon.reels.size() == 4, "4 weapon reels (got %d)" % c.weapon.reels.size())
	# apply_luck uses threshold conversion: every 3 Luck points grant +1 crit-success face.
	# Luck 1 / 3 = 0 (integer division), so 0 bonus crit faces are added; reel 0 keeps its default single crit face.
	var crit: int = 0
	for f: ReelFace in c.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
	_check(crit == 1, "Luck 1 → 1 crit face on reel 0 (got %d)" % crit)

	print(("CHANCER CLASS TEST PASSED" if _failures == 0 else "CHANCER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
