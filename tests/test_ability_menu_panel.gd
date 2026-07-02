extends SceneTree

## View-layer smoke: open_for builds one row per UNLOCKED ability in unlock order, hides locked
## ones entirely (player-locked rule), and rebuilds (never accumulates) on every open.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"warden")
	var c: Combatant = cc.build_combatant(true)
	var plan: MainPhasePlan = MainPhasePlan.new(c, c.ability_cost)
	var panel: AbilityMenuPanel = AbilityMenuPanel.new()

	c.level = 1
	panel.open_for(c, plan)
	_check(panel.row_ids() == ([&"rallying_cry"] as Array[StringName]), "level 1: only the base ability row")
	_check(panel.visible, "open_for shows the panel")

	c.level = 9
	panel.open_for(c, plan)
	var want: Array[StringName] = [&"rallying_cry", &"entangle", &"regrowth", &"bastion"]
	_check(panel.row_ids() == want, "level 9: 4 rows in unlock order (base, L5, L7, L9)")

	panel.open_for(c, plan)
	_check(panel.row_ids() == want, "re-open rebuilds instead of accumulating rows")

	var got: Array[StringName] = []
	panel.ability_pressed.connect(func(id: StringName) -> void: got.append(id))
	panel.press_row_for_test(&"entangle")
	_check(got == ([&"entangle"] as Array[StringName]), "pressing a row emits ability_pressed(id)")

	panel.free()
	quit()
