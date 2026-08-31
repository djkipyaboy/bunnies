extends SceneTree

# Headless test: CharacterClass.resolve_power_stat() (design spec 2026-08-28 §2.1).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_power_stat_resolution.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# No override: melee -> Might.
	var melee: CharacterClass = CharacterClass.new()
	melee.combat_role = &"melee"
	_check(melee.resolve_power_stat() == &"might", "melee, no override -> might (got %s)" % melee.resolve_power_stat())

	# No override: ranged -> Might (the role default, before any per-class override).
	var ranged: CharacterClass = CharacterClass.new()
	ranged.combat_role = &"ranged"
	_check(ranged.resolve_power_stat() == &"might", "ranged, no override -> might (got %s)" % ranged.resolve_power_stat())

	# No override: caster -> Focus.
	var caster: CharacterClass = CharacterClass.new()
	caster.combat_role = &"caster"
	_check(caster.resolve_power_stat() == &"focus", "caster, no override -> focus (got %s)" % caster.resolve_power_stat())

	# Explicit override wins regardless of role.
	var overridden: CharacterClass = CharacterClass.new()
	overridden.combat_role = &"caster"
	overridden.power_stat_override = &"luck"
	_check(overridden.resolve_power_stat() == &"luck", "override always wins over role default (got %s)" % overridden.resolve_power_stat())

	# Real ClassLibrary classes resolve as designed: Ranger -> Finesse, Chancer -> Luck, everyone
	# else follows their role default.
	var expected: Dictionary = {
		&"warrior": &"might", &"vanguard": &"might", &"skirmisher": &"might",
		&"chancer": &"luck", &"ranger": &"finesse",
		&"seer": &"focus", &"warden": &"focus", &"summoner": &"focus",
	}
	for id: StringName in ClassLibrary.IDS:
		var cc: CharacterClass = ClassLibrary.make(id)
		var want: StringName = expected.get(id, &"")
		_check(cc.resolve_power_stat() == want, "%s resolves to %s (got %s)" % [id, want, cc.resolve_power_stat()])

	print(("POWER STAT RESOLUTION TEST PASSED" if _failures == 0 else "POWER STAT RESOLUTION TEST FAILED: %d" % _failures))
	quit(_failures)
