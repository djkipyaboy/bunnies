extends SceneTree

# Headless test: every class/enemy has a valid combat role (spec 2026-06-28 §2). Pure data.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_roles.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

const VALID: Array[StringName] = [&"melee", &"ranged", &"caster"]

func _initialize() -> void:
	# Spot-check the locked assignments.
	_check(ClassLibrary.make(&"warrior").combat_role == &"melee", "warrior -> melee")
	_check(ClassLibrary.make(&"ranger").combat_role == &"ranged", "ranger -> ranged")
	_check(ClassLibrary.make(&"chancer").combat_role == &"ranged", "chancer -> ranged (slingshot)")
	_check(ClassLibrary.make(&"seer").combat_role == &"caster", "seer -> caster")
	_check(ClassLibrary.make(&"warden").combat_role == &"caster", "warden -> caster")

	# Every class has a valid role.
	for id: StringName in ClassLibrary.IDS:
		_check(ClassLibrary.make(id).combat_role in VALID, "class %s has valid role" % id)

	# Every enemy has a valid role; stoat is ranged.
	for id: StringName in EnemyLibrary.IDS:
		_check(EnemyLibrary.role(id) in VALID, "enemy %s has valid role" % id)
	_check(EnemyLibrary.role(&"stoat") == &"ranged", "stoat -> ranged (bow)")
	_check(EnemyLibrary.role(&"ferret") == &"melee", "ferret -> melee (dagger)")

	print(("COMBAT ROLES TEST PASSED" if _failures == 0 else "COMBAT ROLES TEST FAILED: %d" % _failures))
	quit(_failures)
