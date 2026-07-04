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

	# Guaranteed close (player-reported 2026-07-02): pressing ✕ always hides the panel, with no
	# staging side effect — the only reliable way out when the panel covers the button bar or every
	# row is unaffordable.
	panel.open_for(c, plan)
	_check(panel.visible, "re-opened for the close-button check")
	got.clear()
	panel.press_close_for_test()
	_check(not panel.visible, "pressing ✕ hides the panel")
	_check(got.is_empty(), "pressing ✕ does not emit ability_pressed")

	# Bloodwrath's live tooltip (playtest 2026-07-04, player-requested "make the scaling obvious"):
	# the info text appends a computed bonus at the caster's CURRENT hp, sharing
	# Combatant.bloodwrath_bonus_pct() with the caster path so the two numbers can never drift.
	var vg: Combatant = ClassLibrary.make(&"vanguard").build_combatant(true)
	vg.hp = vg.max_hp  # full HP -> 0% missing -> +0% shown
	_check(AbilityMenuPanel._dynamic_suffix(&"bloodwrath", vg).contains("+0% damage"), "bloodwrath suffix at full HP shows +0%")
	vg.hp = maxi(vg.max_hp - int(vg.max_hp * 0.25), 1)  # ~25% missing -> +25% (1%-per-1% formula)
	_check(AbilityMenuPanel._dynamic_suffix(&"bloodwrath", vg).contains("+25% damage"), "bloodwrath suffix at 25%% missing HP shows +25%%")
	_check(AbilityMenuPanel._dynamic_suffix(&"heroic_guard", vg) == "", "no dynamic suffix for other abilities")

	panel.free()
	quit()
