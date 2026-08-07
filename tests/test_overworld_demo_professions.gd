extends SceneTree

## Professions panel wiring in overworld_demo.tscn (2026-08-02 salvaging-and-cooking professions design
## section 5) -- the 'P' hotkey, movement pause, and mutual exclusion with every other panel.
##
## Uses _initialize()/await process_frame (mirroring tests/test_town_demo_old_well.gd) rather than
## _init(), since overworld_demo.gd's _ready() (which builds _professions_panel) hasn't run yet
## immediately after add_child() inside a plain _init() -- confirmed by the identical documented
## reasoning in tests/test_professions_menu_panel.gd. A bare _init() run of this test's original
## literal form threw "Invalid call. Nonexistent function 'is_open' in base 'Nil'" because
## _professions_panel was still null at that point (RED, confirmed empirically before this fix).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/overworld_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	_check(scene._professions_panel != null, "overworld_demo builds a ProfessionsMenuPanel")
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
	# a per-frame auto-trigger poll wasn't gated on every open modal). Reuses the real, already-
	# placed WildBerries GatheringNode (auto_trigger = true) instead of constructing a synthetic
	# interactable, mirroring tests/test_overworld_demo_npcs.gd's established
	# force-into-_tracked-then-drive-a-real-_process()-frame technique.
	scene._auto_trigger_armed = true
	var berries_node: GatheringNode = scene._world.get_node("WildBerries")
	scene._pc._tracked.append(berries_node)

	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "Professions opened, ahead of the auto-trigger gate check")
	scene._process(0.016)
	_check(not scene._foraging_panel.is_open(), "the armed WildBerries auto-trigger does NOT fire while Professions is open")
	_check(not berries_node.is_queued_for_deletion(), "WildBerries is still alive -- untouched by _process() while Professions is open")

	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "Professions closed")
	scene._process(0.016)
	_check(scene._foraging_panel.is_open(), "closing Professions lets the very next _process() tick fire the still-armed auto-trigger (sanity check the gate isn't permanently blocking)")
	scene._pc._tracked.erase(berries_node)
	scene._foraging_panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)
	scene._foraging_panel.press_bank_for_test()
	_check(not scene._foraging_panel.is_open(), "banking the Foraging panel closes it, cleaning up after the regression check")

	# Task 8 (2026-08-07 professions-playtest-fixes): none of the four panel toggles should be able
	# to open on top of a live dialogue -- town_demo.gd's identical functions already guard on this;
	# overworld_demo.gd's did not. Reuses the real friendly Villager already placed by
	# overworld_demo.gd's _build_npcs() (mirrors tests/test_overworld_demo_npcs.gd's own technique
	# for opening a real dialogue via _on_dialogue_requested).
	var wanderer: Villager = scene._world.get_node("OverworldWanderer")
	scene._on_dialogue_requested(wanderer.dialogue, wanderer)
	_check(scene._dialogue_box.is_open(), "dialogue is open, ahead of the guard check")

	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "_toggle_professions() is a no-op while dialogue is open")
	scene._toggle_inventory()
	_check(not scene._inventory_panel.visible, "_toggle_inventory() is a no-op while dialogue is open")
	scene._toggle_stats()
	_check(not scene._inventory_panel.visible, "_toggle_stats() is a no-op while dialogue is open")
	scene._toggle_talents()
	_check(not scene._talent_panel.visible, "_toggle_talents() is a no-op while dialogue is open")

	scene._dialogue_box.close()
	_check(not scene._dialogue_box.is_open(), "dialogue closed, sanity check ahead of the re-enable check")
	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "_toggle_professions() works again once dialogue is closed")
	scene._toggle_professions()

	print("ok overworld_demo Professions wiring smoke test complete")
	quit()
