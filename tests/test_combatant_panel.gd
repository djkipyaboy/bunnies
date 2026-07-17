extends SceneTree

# Headless test: CombatantPanel.set_ally_targeted (2026-07-16 combat item-use targeting design §3.6)
# — a green-bordered stylebox override distinct from the existing set_targeted's red border, so the
# enemy-target and ally-target outlines never look alike even if both were ever true on one panel.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var panel: CombatantPanel = CombatantPanel.new()

	_check(not panel.has_theme_stylebox_override("panel"), "no override before any targeting call")

	panel.set_ally_targeted(true)
	_check(panel.has_theme_stylebox_override("panel"), "set_ally_targeted(true) applies a stylebox override")
	var ally_sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	_check(ally_sb.border_color == Color(0.4, 0.85, 0.4), "ally-target border is green")

	panel.set_ally_targeted(false)
	_check(not panel.has_theme_stylebox_override("panel"), "set_ally_targeted(false) removes the override")

	panel.set_targeted(true)
	var enemy_sb: StyleBoxFlat = panel.get_theme_stylebox("panel")
	_check(enemy_sb.border_color == Color(0.92, 0.42, 0.32), "set_targeted's border is red (sanity: unchanged by this pass)")
	_check(enemy_sb.border_color != ally_sb.border_color, "ally-target and enemy-target borders are visually distinct colors")

	panel.set_targeted(false)
	_check(not panel.has_theme_stylebox_override("panel"), "set_targeted(false) removes the override")

	panel.free()
	quit()
