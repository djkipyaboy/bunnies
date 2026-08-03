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

	# Regression (task-8 review finding): _process()'s auto-trigger firing poll must be gated on
	# the Professions panel too, not just _unhandled_input()'s interact-key dispatch -- this project
	# hit and fixed the identical bug class 2026-07-13 ("Encounter started" logged 23 times because
	# a per-frame auto-trigger poll wasn't gated on every open modal). Uses a minimal synthetic
	# Interactable (auto_trigger = true) rather than a real dungeon OverworldEnemy, since driving a
	# real enemy's interact() awaits a fade then calls change_scene_to_file() -- exactly what
	# tests/test_overworld_demo_npcs.gd's own doc comment says to avoid inside a test's SceneTree.
	scene._auto_trigger_armed = true
	var probe := Interactable.new()
	probe.name = "AutoTriggerAssertionProbe"
	probe.auto_trigger = true
	# Placed exactly on the PC so it strictly wins Interactable.nearest() over whatever the
	# dungeon's own real fixtures (e.g. the entrance Stairs) may already be tracking from physics
	# overlap during the two awaited process_frame calls above.
	probe.global_position = scene._pc.global_position
	scene._floors[scene._current_floor].add_child(probe)
	scene._pc._tracked.append(probe)
	var fired: Array = [false]
	probe.interacted.connect(func() -> void: fired[0] = true)

	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "Professions opened, ahead of the auto-trigger gate check")
	scene._process(0.016)
	_check(not fired[0], "the armed auto-trigger probe does NOT fire while Professions is open")

	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "Professions closed")
	scene._process(0.016)
	_check(fired[0], "closing Professions lets the very next _process() tick fire the still-armed auto-trigger (sanity check the gate isn't permanently blocking)")
	scene._pc._tracked.erase(probe)
	probe.queue_free()

	print("ok dungeon_demo Professions wiring smoke test complete")
	quit()
