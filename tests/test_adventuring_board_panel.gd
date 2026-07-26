extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_entry(title: String, category: QuestBoardEntry.Category, body: String) -> QuestBoardEntry:
	var entry := QuestBoardEntry.new()
	entry.title = title
	entry.category = category
	entry.body_text = body
	return entry

func _init() -> void:
	var current := _make_entry("Clear the Cellar", QuestBoardEntry.Category.CURRENT, "Coming soon.")
	var side := _make_entry("Lost Cat", QuestBoardEntry.Category.SIDE, "Coming soon.")
	var recap := _make_entry("How We Got Here", QuestBoardEntry.Category.RECAP, "Coming soon.")
	var entries: Array[QuestBoardEntry] = [current, side, recap]

	# Pure static grouping logic first — no node/tree involved.
	var groups: Dictionary = AdventuringBoardPanel.group_by_category(entries)
	_check(groups[QuestBoardEntry.Category.CURRENT].size() == 1, "one CURRENT entry grouped")
	_check(groups[QuestBoardEntry.Category.CURRENT][0] == current, "CURRENT group holds the right entry")
	_check(groups[QuestBoardEntry.Category.SIDE][0] == side, "SIDE group holds the right entry")
	_check(groups[QuestBoardEntry.Category.RECAP][0] == recap, "RECAP group holds the right entry")

	var empty_groups: Dictionary = AdventuringBoardPanel.group_by_category([])
	_check(empty_groups[QuestBoardEntry.Category.CURRENT].size() == 0, "empty input groups to empty buckets")

	# Instance behavior — built via .new(), never added to a live tree.
	var panel := AdventuringBoardPanel.new()
	panel.open_for(entries)
	_check(panel.visible, "open_for() shows the panel")

	# GDScript lambdas capture outer locals BY VALUE — a plain `var selected` reassigned
	# inside the lambda would never propagate out. Route it through a one-element array.
	var selected: Array[QuestBoardEntry] = [null]
	panel.entry_selected.connect(func(entry: QuestBoardEntry) -> void: selected[0] = entry)
	panel.press_row_for_test(0)
	_check(selected[0] == current, "pressing row 0 selects the first entry (CURRENT header comes first)")

	# Party Selection button (2026-07-12, player-requested companion recruitment) — re-open first
	# since close() above hid it, and re-open rebuilds every row from scratch anyway.
	# Fixed 2026-07-26: this used to increment a plain `int` inside the lambda below, which never
	# propagates out (same GDScript closure-capture-by-value gotcha documented at the `selected` var
	# above) — the assertion below always failed regardless of whether the signal actually fired.
	# Root-caused during the 2026-07-25 endgame-level-up-town work; fixed here with the same
	# one-element-array workaround.
	panel.open_for(entries)
	var party_selection_pressed_count: Array[int] = [0]
	panel.party_selection_pressed.connect(func() -> void: party_selection_pressed_count[0] += 1)
	panel.press_party_selection_for_test()
	_check(party_selection_pressed_count[0] == 1, "pressing Party Selection emits party_selection_pressed")

	# Plain-int lambda capture doesn't propagate out in GDScript (see the `selected` note above);
	# use the same one-element-array workaround already established elsewhere in this codebase
	# (tests/test_random_encounter_panel.gd, tests/test_vendor_prompt_panel.gd).
	var endgame_level_up_pressed_count: Array[int] = [0]
	panel.endgame_level_up_pressed.connect(func() -> void: endgame_level_up_pressed_count[0] += 1)
	panel.press_endgame_level_up_for_test()
	_check(endgame_level_up_pressed_count[0] == 1, "pressing Level Up to Endgame emits endgame_level_up_pressed")

	panel.close()
	_check(not panel.visible, "close() hides the panel")
	panel.free()  # never entered the tree, so free manually (matches test_ability_menu_panel.gd)
	quit()
