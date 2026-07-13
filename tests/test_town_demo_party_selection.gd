extends SceneTree

## Headless smoke test: Party Selection wiring in town_demo.gd (2026-07-12, player-requested
## companion recruitment via the Town Adventuring Board) — the board's new Party Selection button
## opens PartySelectionPanel, add/remove requests mutate the live _companions/_bench, PC movement
## pauses while it's open, and pressing interact closes it (mirroring the board panel's own
## close-on-interact behavior).

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		_check(town._party_selection_panel != null, "PartySelectionPanel is built")
		_check(not town._party_selection_panel.visible, "PartySelectionPanel starts hidden")
		_check(town._bench.size() > 0, "the demo seeds a non-empty bench of precreated companions")

		var board: AdventuringBoard = town._exterior.get_node("AdventuringBoard")
		town._on_board_opened(board.entries)
		_check(town._board_panel.is_open(), "board opens normally")

		town._board_panel.press_party_selection_for_test()
		_check(not town._board_panel.is_open(), "opening Party Selection closes the board panel")
		_check(town._party_selection_panel.is_open(), "Party Selection panel is now open")
		_check(town._pc.movement_paused_for_test(), "PC movement stays paused across the board -> Party Selection handoff")

		var starting_companion_count: int = town._companions.size()
		var recruit: Combatant = town._bench[0]
		town._party_selection_panel.press_bench_row_for_test(0)
		_check(town._companions.has(recruit), "pressing an Add row recruits that companion into the party")
		_check(not town._bench.has(recruit), "the recruited companion leaves the bench")
		_check(town._companions.size() == starting_companion_count + 1, "party size grows by exactly one")

		# The panel rebuilds after every add/remove — re-fetch fresh row indices rather than assume
		# stale ones still point at the same buttons.
		town._party_selection_panel.press_party_row_for_test(town._companions.find(recruit))
		_check(not town._companions.has(recruit), "pressing Remove sends the companion back to the bench")
		_check(town._bench.has(recruit), "the removed companion is back on the bench")
		_check(town._companions.size() == starting_companion_count, "party size returns to its starting count")

		# Recruiting up to the 2-companion cap disables further Add rows (PartySelectionPanel.
		# party_full()) — exercise it through the real handler, not just the panel's own unit test.
		while town._companions.size() < 2 and town._bench.size() > 0:
			town._on_add_companion_requested(town._bench[0])
		if town._bench.size() > 0:
			_check(town._party_selection_panel.bench_row_disabled_for_test(0), "Add rows disable once the party holds 2 companions")
			town._on_add_companion_requested(town._bench[0])
			_check(town._companions.size() == 2, "add_companion_requested is a no-op once the party is already full")

		# Interact closes Party Selection the same way it closes the board panel.
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		town._unhandled_input(interact_event)
		_check(not town._party_selection_panel.is_open(), "pressing interact closes the Party Selection panel")
		_check(not town._pc.movement_paused_for_test(), "closing Party Selection resumes PC movement")

	if _frames >= 5:
		print("ok town_demo Party Selection smoke test complete")
		_instance.free()
		return true
	return false
