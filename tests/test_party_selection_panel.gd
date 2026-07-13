extends SceneTree

## View-layer smoke: PartySelectionPanel (2026-07-12, player-requested companion recruitment via
## the Town Adventuring Board) — lists the PC (non-removable), current companions (Remove), and
## bench companions (Add, disabled once the party is full).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.display_name = "Martin"

	var comp1: Combatant = Combatant.new()
	comp1.display_name = "Basil"

	var bench1: Combatant = Combatant.new()
	bench1.display_name = "Sunflash"
	var bench2: Combatant = Combatant.new()
	bench2.display_name = "Cheek"

	_check(not PartySelectionPanel.party_full([]), "an empty party is not full")
	_check(not PartySelectionPanel.party_full([comp1]), "1 companion (of 2 max) is not full")
	_check(PartySelectionPanel.party_full([comp1, bench1]), "2 companions (the max) IS full")

	var panel: PartySelectionPanel = PartySelectionPanel.new()
	panel.open_for(pc, [comp1], [bench1, bench2])

	_check(panel.visible, "open_for shows the panel")
	_check(panel.party_row_count_for_test() == 1, "one Remove row per current companion")
	_check(panel.bench_row_count_for_test() == 2, "one Add row per bench companion")
	_check(not panel.bench_row_disabled_for_test(0), "Add rows are enabled while the party has room")

	var added: Array[Combatant] = []
	panel.add_companion_requested.connect(func(c: Combatant) -> void: added.append(c))
	panel.press_bench_row_for_test(0)
	_check(added == [bench1], "pressing a bench row emits add_companion_requested with that companion")

	var removed: Array[Combatant] = []
	panel.remove_companion_requested.connect(func(c: Combatant) -> void: removed.append(c))
	panel.press_party_row_for_test(0)
	_check(removed == [comp1], "pressing a party row emits remove_companion_requested with that companion")

	# A full party (2 companions) disables every bench "Add" row.
	panel.open_for(pc, [comp1, bench1], [bench2])
	_check(panel.bench_row_disabled_for_test(0), "Add rows disable once the party already holds 2 companions")

	panel.free()
	quit()
