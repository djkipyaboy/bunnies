extends SceneTree

## View-layer smoke: ItemMenuPanel builds one row per distinct item type the party owns, toggling
## via item_pressed. Mirrors AbilityMenuPanel's shape (tests/test_ability_menu_panel.gd) minus the
## affordability/cooldown states items don't need (every listed item is stageable by definition of
## being owned with quantity > 0).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_item_menu_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 25
	potion.quantity = 3
	inv.items = [potion]

	var c: Combatant = Combatant.new()
	c.resource_pool = ResourcePool.new()
	c.display_name = "Basil"
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	var panel: ItemMenuPanel = ItemMenuPanel.new()

	panel.open_for(plan, inv, c)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "one row per owned item type")
	_check(panel.visible, "open_for shows the panel")

	panel.open_for(plan, inv, c)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "re-open rebuilds instead of accumulating rows")

	var got: Array[StringName] = []
	panel.item_pressed.connect(func(item_type: StringName) -> void: got.append(item_type))
	panel.press_row_for_test(&"healing_potion")
	_check(got == ([&"healing_potion"] as Array[StringName]), "pressing a row emits item_pressed(item_type)")

	plan.toggle_item(&"healing_potion")
	panel.open_for(plan, inv, c)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "row list unaffected by staging")
	var staged_btn: Button = panel._row_buttons[&"healing_potion"]
	_check(staged_btn.text.contains("✓"), "staged row's button text shows the checkmark")
	_check(staged_btn.modulate == ItemMenuPanel.COLOR_STAGED, "staged row's button is tinted COLOR_STAGED")

	# Live, target-aware description (2026-07-16 design §3.7): names the CURRENT ally target and
	# spells out the reel odds, replacing the old "lowest-HP% ally" auto-target text.
	panel.open_for(plan, inv, c)
	_check(_find_info_text(panel).find("Heals Basil for 25 HP") != -1, "description names the passed ally_target (got '%s')" % _find_info_text(panel))
	_check(_find_info_text(panel).find("90%") != -1 and _find_info_text(panel).find("10%") != -1, "description states the 90/10 reel odds")
	_check(_find_info_text(panel).find("1.5") != -1, "description states the crit multiplier")

	# A null ally_target (e.g. no PC turn active yet) falls back to a generic phrase, no crash.
	panel.open_for(plan, inv, null)
	_check(_find_info_text(panel).find("your target") != -1, "null ally_target falls back to a generic phrase (got '%s')" % _find_info_text(panel))

	panel.open_for(plan, inv, c)
	_check(panel.visible, "re-opened for the close-button check")
	got.clear()
	panel.press_close_for_test()
	_check(not panel.visible, "pressing ✕ hides the panel")
	_check(got.is_empty(), "pressing ✕ does not emit item_pressed")

	# An empty inventory renders zero rows, no crash.
	var empty_inv: PartyInventory = PartyInventory.new()
	panel.open_for(plan, empty_inv, c)
	_check(panel.row_types().is_empty(), "zero owned items -> zero rows")

	panel.free()
	quit()

## Test helper: finds the info Label's text among the panel's children (there's exactly one row here).
## Skips nodes already queued for deletion — open_for() clears old children via queue_free(), which
## is DEFERRED (not immediate), so stale labels from a prior open_for() call are still present in
## get_children() at this point in a synchronous test; is_queued_for_deletion() distinguishes them
## from the panel's actual current row.
func _find_info_text(panel: ItemMenuPanel) -> String:
	for child in panel.get_children():
		if child is Label and not child.is_queued_for_deletion() and (child as Label).text.begins_with("Heals"):
			return (child as Label).text
	return ""
