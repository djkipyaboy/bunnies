# tests/test_tutorial_full_sequence.gd
extends SceneTree

## Full end-to-end integration test for the tutorial quest (2026-08-10 quest-system-and-tutorial
## design) — proves every piece built across this plan's 13 tasks works TOGETHER: auto-start on a
## fresh town_demo load → each of the 9 objectives completing via its real trigger → auto-complete
## → reward_amber granted. Mirrors test_lost_cat_quest_full_sequence.gd's shape.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	_check(inv.has_accepted_quest(&"tutorial"), "1. auto-started on load")
	var amber_before: int = inv.amber

	# 2. move
	Input.action_press("move_right")
	scene._pc._physics_process(0.016)
	Input.action_release("move_right")
	_check(inv.is_objective_complete(&"tutorial", &"move"), "2. move objective complete")

	# 3. open_inventory
	scene._toggle_inventory()
	_check(inv.is_objective_complete(&"tutorial", &"open_inventory"), "3. open_inventory objective complete")
	scene._toggle_inventory()

	# 4. equip_gear
	var gear := Gear.new()
	gear.display_name = "Tutorial Test Cap"
	gear.slot = Gear.Slot.HEADWEAR
	inv.give_gear(gear)
	scene._inventory_panel.select_item_for_test(gear, false)
	scene._inventory_panel.equip_selected_for_test(scene._pc_combatant, scene._inventory_panel.gear_slot_index_for(gear.slot))
	_check(inv.is_objective_complete(&"tutorial", &"equip_gear"), "4. equip_gear objective complete")

	# 5. open_event_log
	var log_event := InputEventAction.new()
	log_event.action = &"toggle_event_log"
	log_event.pressed = true
	scene._event_log_panel.visible = false
	scene._unhandled_input(log_event)
	_check(inv.is_objective_complete(&"tutorial", &"open_event_log"), "5. open_event_log objective complete")

	# 6. open_professions
	scene._toggle_professions()
	_check(inv.is_objective_complete(&"tutorial", &"open_professions"), "6. open_professions objective complete")
	scene._toggle_professions()

	# 7. open_legend
	scene._toggle_legend()
	_check(inv.is_objective_complete(&"tutorial", &"open_legend"), "7. open_legend objective complete")
	scene._toggle_legend()

	# 8. visit_shop
	var shopkeeper: Villager = null
	for child in scene._interior.get_children():
		if child is Villager and (child as Villager).is_vendor:
			shopkeeper = child
	scene._on_vendor_interacted(shopkeeper.dialogue, shopkeeper)
	_check(inv.is_objective_complete(&"tutorial", &"visit_shop"), "8. visit_shop objective complete")
	_check(not inv.has_completed_quest(&"tutorial"), "still not complete — visit_board and win_fight remain")

	# 9. visit_board
	scene._on_board_opened(scene._make_quest_entries())
	_check(inv.is_objective_complete(&"tutorial", &"visit_board"), "9. visit_board objective complete")
	_check(not inv.has_completed_quest(&"tutorial"), "still not complete — win_fight is the last objective")

	# 10. win_fight — the final objective; completing it must auto-complete the quest and grant the
	# reward. town_demo has no _on_combat_ended of its own (that's combat.gd, exercised directly by
	# Task 13's own test) — call PartyInventory the same way that real hook does, to prove the
	# auto-complete/reward chain fires from the LAST objective regardless of which trigger reaches it.
	inv.complete_objective(&"tutorial", &"win_fight")
	_check(inv.is_objective_complete(&"tutorial", &"win_fight"), "10. win_fight objective complete")
	_check(inv.has_completed_quest(&"tutorial"), "completing the last objective auto-completes the tutorial quest")

	var tutorial_quest: Quest = QuestLibrary.get_quest(&"tutorial")
	_check(inv.amber == amber_before + tutorial_quest.reward_amber, "completing the tutorial grants its reward_amber (got %d, expected %d)" % [inv.amber, amber_before + tutorial_quest.reward_amber])

	quit()
