extends SceneTree

# Headless test: RoleVisuals.label/color — selection-screen combat-role badge mapping
# (spec 2026-06-28 §4.2). Pure/static; no scene.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_role_visuals.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(RoleVisuals.label(&"melee") == "MELEE", "melee label")
	_check(RoleVisuals.label(&"ranged") == "RANGED", "ranged label")
	_check(RoleVisuals.label(&"caster") == "CASTER", "caster label")
	_check(RoleVisuals.label(&"nonsense") == "—", "unknown role label -> dash")

	# Each known role has a distinct, non-white identity color; unknown -> grey default.
	var m: Color = RoleVisuals.color(&"melee")
	var r: Color = RoleVisuals.color(&"ranged")
	var c: Color = RoleVisuals.color(&"caster")
	_check(m != r and r != c and m != c, "three roles have distinct colors")
	_check(RoleVisuals.color(&"nonsense") == Color(0.5, 0.5, 0.5), "unknown role color -> grey")

	print(("ROLE VISUALS TEST PASSED" if _failures == 0 else "ROLE VISUALS TEST FAILED: %d" % _failures))
	quit(_failures)
