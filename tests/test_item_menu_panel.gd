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
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	var panel: ItemMenuPanel = ItemMenuPanel.new()

	panel.open_for(plan, inv)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "one row per owned item type")
	_check(panel.visible, "open_for shows the panel")

	panel.open_for(plan, inv)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "re-open rebuilds instead of accumulating rows")

	var got: Array[StringName] = []
	panel.item_pressed.connect(func(item_type: StringName) -> void: got.append(item_type))
	panel.press_row_for_test(&"healing_potion")
	_check(got == ([&"healing_potion"] as Array[StringName]), "pressing a row emits item_pressed(item_type)")

	plan.toggle_item(&"healing_potion")
	panel.open_for(plan, inv)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "row list unaffected by staging")

	panel.open_for(plan, inv)
	_check(panel.visible, "re-opened for the close-button check")
	got.clear()
	panel.press_close_for_test()
	_check(not panel.visible, "pressing ✕ hides the panel")
	_check(got.is_empty(), "pressing ✕ does not emit item_pressed")

	# An empty inventory renders zero rows, no crash.
	var empty_inv: PartyInventory = PartyInventory.new()
	panel.open_for(plan, empty_inv)
	_check(panel.row_types().is_empty(), "zero owned items -> zero rows")

	panel.free()
	quit()
