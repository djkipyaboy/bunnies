extends SceneTree

# Headless test for the Summoner class shell (2026-08-16 minion-summoning-class spec §3). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_summoner_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(&"summoner" in ClassLibrary.IDS, "summoner is registered in ClassLibrary.IDS")
	var cls: CharacterClass = ClassLibrary.make(&"summoner")
	_check(cls != null, "ClassLibrary.make(&summoner) returns a real CharacterClass")
	_check(cls.ability_id == &"ember_minion", "summoner base ability is ember_minion (got %s)" % cls.ability_id)
	_check(cls.ability_resource == &"mana", "summoner's ability resource is mana (got %s)" % cls.ability_resource)

	var c: Combatant = cls.build_combatant(true)
	_check(c.ability_id == &"ember_minion", "built Combatant carries the ember_minion ability_id")
	_check(c.resource_pool != null, "built Combatant has a resource pool to pay the summon cost")

	_check(cls.ultimate_id == &"grand_sacrifice", "summoner ultimate_id is grand_sacrifice (got %s)" % cls.ultimate_id)
	_check(cls.extra_abilities.size() == 3, "summoner has 3 extra_abilities (got %d)" % cls.extra_abilities.size())

	var dew: AbilityDef = cls.extra_abilities[0]
	_check(dew.id == &"dew_minion", "extra_abilities[0].id is dew_minion (got %s)" % dew.id)
	_check(dew.unlock_level == 2, "dew_minion unlocks at level 2 (got %d)" % dew.unlock_level)
	_check(dew.cost == 5, "dew_minion costs 5 (got %d)" % dew.cost)
	_check(dew.resource == &"mana", "dew_minion resource is mana (got %s)" % dew.resource)

	var misfortune: AbilityDef = cls.extra_abilities[1]
	_check(misfortune.id == &"misfortune_minion", "extra_abilities[1].id is misfortune_minion (got %s)" % misfortune.id)
	_check(misfortune.unlock_level == 3, "misfortune_minion unlocks at level 3 (got %d)" % misfortune.unlock_level)
	_check(misfortune.cost == 4, "misfortune_minion costs 4 (got %d)" % misfortune.cost)
	_check(misfortune.resource == &"mana", "misfortune_minion resource is mana (got %s)" % misfortune.resource)

	var hasty: AbilityDef = cls.extra_abilities[2]
	_check(hasty.id == &"hasty_minion", "extra_abilities[2].id is hasty_minion (got %s)" % hasty.id)
	_check(hasty.unlock_level == 4, "hasty_minion unlocks at level 4 (got %d)" % hasty.unlock_level)
	_check(hasty.cost == 6, "hasty_minion costs 6 (got %d)" % hasty.cost)
	_check(hasty.resource == &"mana", "hasty_minion resource is mana (got %s)" % hasty.resource)

	_check(cls.display_name == "Harvester", "summoner class display_name is now Harvester (got %s)" % cls.display_name)
	_check(cls.weapon_display_name == "Scythe", "summoner weapon_display_name is now Scythe (got %s)" % cls.weapon_display_name)
	_check(is_equal_approx(cls.weapon_base_damage, 14.0), "summoner weapon_base_damage retuned to 14.0 (got %f)" % cls.weapon_base_damage)
	_check(cls.reel_count == 2, "summoner keeps its 2-reel baseline (got %d)" % cls.reel_count)

	print(("SUMMONER CLASS TEST PASSED" if _failures == 0 else "SUMMONER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
