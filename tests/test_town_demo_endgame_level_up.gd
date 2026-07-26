extends SceneTree

## Headless test proving "Level Up to Endgame" is wired for REAL inside town_demo.tscn (not just
## the isolated AdventuringBoardPanel unit test) — this project has repeatedly found wiring bugs
## that a manually-constructed-object test alone would miss (e.g. the 2026-07-12 bench-wiped-after-
## combat bug, 2026-07-17 shop-stock-reset bug — both only caught by driving the REAL scene path).

var _town: TownDemo
var _failures: int = 0

func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_town = scene.instantiate() as TownDemo
	root.add_child(_town)
	await process_frame
	await process_frame

	_check(_town._pc_combatant.level == 9, "sanity: the demo seeds the PC at level 9")
	_check(_town._companions.size() > 0, "sanity: the demo seeds at least 1 active companion")
	_check(_town._companions[0].level == 3, "sanity: the demo seeds the active companion at level 3")
	_check(_town._bench.size() > 0, "sanity: the demo seeds a non-empty bench")
	for c: Combatant in _town._bench:
		_check(c.level == 3, "sanity: every benched companion starts at level 3 (%s)" % c.display_name)

	_town._on_board_opened([])   # real production entry point (ignores its arg, recomputes fresh)
	_check(_town._board_panel.visible, "the real Adventuring Board opens")
	_town._board_panel.press_endgame_level_up_for_test()

	_check(_town._pc_combatant.level == Combatant.MAX_LEVEL, "the PC is now level %d" % Combatant.MAX_LEVEL)
	for c: Combatant in _town._companions:
		_check(c.level == Combatant.MAX_LEVEL, "active companion %s is now level %d" % [c.display_name, Combatant.MAX_LEVEL])
	for c: Combatant in _town._bench:
		_check(c.level == Combatant.MAX_LEVEL, "benched companion %s is now level %d" % [c.display_name, Combatant.MAX_LEVEL])

	_town.free()
	print(("TOWN DEMO ENDGAME LEVEL UP TEST PASSED" if _failures == 0 else "TOWN DEMO ENDGAME LEVEL UP TEST FAILED: %d" % _failures))
	quit(_failures)
