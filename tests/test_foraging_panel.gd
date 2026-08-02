extends SceneTree

## ForagingPanel: view over ForagingMinigame (2026-08-01 gathering-profession-minigames spec
## section 2). Mirrors tests/test_random_encounter_panel.gd's SceneTree/_initialize()/press_*_for_test
## structure.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()

	var panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(panel)
	await process_frame

	panel.open_for(&"forage_herb", "Wild Berries", 1, inv)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visible")

	var completed_events: Array = []   # [{"name": String, "quantity": int}]
	panel.foraging_completed.connect(func(item_name: String, quantity: int) -> void:
		completed_events.append({"name": item_name, "quantity": quantity}))

	panel.press_bank_for_test()
	_check(not panel.visible, "pressing Bank hides the panel")
	_check(inv.materials.size() == 1, "banking grants exactly one CraftingMaterial into the inventory")
	var m: CraftingMaterial = inv.materials[0]
	_check(m.material_type == &"forage_herb", "granted material carries the node's material_type")
	_check(m.display_name == "Wild Berries", "granted material carries the node's display name")
	_check(completed_events.size() == 1, "banking emits foraging_completed exactly once")
	_check(completed_events[0]["name"] == "Wild Berries", "foraging_completed carries the display name")

	# Re-opening for a second node proves state resets cleanly between uses (same node reused by
	# the driving scene across multiple GatheringNode interactions, mirroring RandomEncounterPanel).
	panel.open_for(&"fish_meat", "Freshwater Fish", 1, inv)
	_check(panel.visible, "re-opening shows the panel again")
	panel.press_shake_for_test()
	panel.press_bank_for_test()
	_check(inv.materials.size() == 2, "a second, independent bank grants a second stacked-or-separate material entry")
	_check(completed_events.size() == 2, "foraging_completed fires again on the second bank")

	# tiers_override forces a deterministic Bumper Crop bank, proving quality_tier actually
	# propagates from ForagingMinigame's outcome onto the granted CraftingMaterial (not just
	# quantity/name, which the untargeted real-pool banks above already exercised).
	var bumper_only: Array[Dictionary] = [{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}]
	var inv2: PartyInventory = PartyInventory.new()
	panel.open_for(&"forage_herb", "Wild Berries", 3, inv2, bumper_only)
	panel.press_bank_for_test()
	var bumper_material: CraftingMaterial = inv2.materials[0]
	_check(bumper_material.quantity == 6, "a x2 Bumper Crop bank on a base quantity of 3 grants 6 (3 * 2)")
	_check(bumper_material.quality_tier == 1, "a Bumper Crop bank stamps quality_tier == 1 onto the granted material")

	panel.free()
	quit()
