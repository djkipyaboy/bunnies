extends SceneTree

# Headless test: CombatantPanel.set_ally_targeted (2026-07-16 combat item-use targeting design §3.6)
# — a green-bordered stylebox override distinct from the existing set_targeted's red border, so the
# enemy-target and ally-target outlines never look alike even if both were ever true on one panel.
#
# Also: the panel-height/status-row-clipping regression (final-review finding, playtest 2026-07-31) —
# adding _riposte_label pushed the VBox's real minimum height past the panel's own fixed height, so
# the status-effects RichTextLabel silently clipped. Codified here as a standing invariant: the
# VBox's combined minimum height must always fit within the panel's own custom_minimum_size.y.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_panel.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var panel: CombatantPanel = CombatantPanel.new()
	root.add_child(panel)
	await process_frame
	await process_frame

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

	# --- Panel-height / status-row-clipping invariant ---
	var c: Combatant = Combatant.new()
	c.display_name = "TestCombatant"
	c.base_stats = Stats.new()
	c.base_max_hp = 100
	c.apply_stats()
	c.start_combat()
	c.bonus_meter = BonusMeter.new()  # is_visible defaults true — every optional row (meter) is present

	var full_panel: CombatantPanel = CombatantPanel.new()
	root.add_child(full_panel)
	await process_frame
	await process_frame
	full_panel.bind(c)
	await process_frame

	var box: VBoxContainer = full_panel.get_child(0) as VBoxContainer
	_check(box != null, "the panel's sole direct child is its content VBoxContainer")
	if box != null:
		var combined_min_h: float = box.get_combined_minimum_size().y
		_check(combined_min_h <= full_panel.custom_minimum_size.y,
			"VBox combined minimum height (%.1f) fits within the panel's own height (%.1f) — no silent clipping" % [combined_min_h, full_panel.custom_minimum_size.y])

	full_panel.free()

	print(("COMBATANT PANEL TEST PASSED" if _failures == 0 else "COMBATANT PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
