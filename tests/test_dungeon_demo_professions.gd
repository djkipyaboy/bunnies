extends SceneTree

## Professions panel wiring in dungeon_demo.tscn (2026-08-02 salvaging-and-cooking professions design
## section 5) -- the 'P' hotkey, movement pause, and mutual exclusion with every other panel.
##
## Uses _initialize()/await process_frame (mirroring tests/test_town_demo_old_well.gd) rather than
## _init(), since dungeon_demo.gd's _ready() (which builds _professions_panel) hasn't run yet
## immediately after add_child() inside a plain _init() -- confirmed by the identical documented
## reasoning in tests/test_professions_menu_panel.gd. A bare _init() run of this test's original
## literal form threw "Invalid call. Nonexistent function 'is_open' in base 'Nil'" because
## _professions_panel was still null at that point (RED, confirmed empirically before this fix).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/dungeon_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(scene._professions_panel != null, "dungeon_demo builds a ProfessionsMenuPanel")
	_check(not scene._professions_panel.is_open(), "the panel starts closed")

	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "_toggle_professions() opens the panel")
	_check(scene._pc.movement_paused_for_test(), "opening the panel pauses PC movement")

	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "_toggle_professions() again closes the panel")
	_check(not scene._pc.movement_paused_for_test(), "closing the panel resumes PC movement")

	# Mutual exclusion: opening Inventory blocks Professions, and vice versa.
	scene._toggle_inventory()
	_check(scene._inventory_panel.visible, "Inventory opened")
	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "_toggle_professions() is a no-op while Inventory is open")
	scene._toggle_inventory()

	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "Professions opened")
	scene._toggle_inventory()
	_check(not scene._inventory_panel.visible, "_toggle_inventory() is a no-op while Professions is open")
	scene._toggle_professions()

	print("ok dungeon_demo Professions wiring smoke test complete")
	quit()
