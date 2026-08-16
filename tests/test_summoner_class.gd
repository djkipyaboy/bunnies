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

	print(("SUMMONER CLASS TEST PASSED" if _failures == 0 else "SUMMONER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
