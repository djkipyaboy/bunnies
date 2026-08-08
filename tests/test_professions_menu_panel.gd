extends SceneTree

## ProfessionsMenuPanel: Salvaging's UI (2026-08-02 salvaging-and-cooking professions design section
## 5). This task covers only the Salvaging section -- a later plan (Cooking) adds a second section.
##
## Uses _initialize()/await process_frame (mirroring tests/test_tempering_reels_panel.gd and
## tests/test_foraging_panel.gd) rather than _init(), since ProfessionsMenuPanel's own _ready()
## constructs its child TemperingReelsPanel -- a plain _init() runs before the SceneTree has
## processed a frame, so _tempering_panel would still be null when open_for() is called.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

## Asserts a horizontal row of buttons both fits inside the panel AND never overlaps its own
## neighbours, measured on each Button's REAL laid-out `size.x` rather than `custom_minimum_size.x`.
## `custom_minimum_size` is only a FLOOR -- Godot renders a Button at max(custom_minimum_size, text
## width + theme margins) -- which is exactly how "Uncommon" (99px rendered inside an 80px minimum)
## overlapping "Rare", and "Headwear  ✓" (108px) overlapping "Cloak", both survived the previous,
## custom_minimum_size-based version of these assertions (2026-08-08 professions-playtest-round2
## final whole-branch review). Requires an `await process_frame` since the panel's last rebuild, so
## `size` reflects a real layout pass.
func _check_row_no_overlap(buttons: Dictionary, keys: Array, label: String) -> void:
	var ordered: Array[Button] = []
	for k in keys:
		ordered.append(buttons[k])
	for i in range(ordered.size()):
		var b: Button = ordered[i]
		# Guards against a false pass: an un-laid-out Button reports size.x == 0, which would satisfy
		# every non-overlap assertion below no matter how broken the real layout is.
		_check(b.size.x > 0.0 and b.size.x >= b.custom_minimum_size.x,
			"%s: '%s' is really laid out (rendered width %f, minimum %f)" % [label, b.text, b.size.x, b.custom_minimum_size.x])
		_check(b.position.x + b.size.x <= ProfessionsMenuPanel.PANEL_W - ProfessionsMenuPanel.PAD,
			"%s: '%s' stays inside the panel (right edge %f, panel inner edge %f)" % [label, b.text, b.position.x + b.size.x, ProfessionsMenuPanel.PANEL_W - ProfessionsMenuPanel.PAD])
		if i + 1 < ordered.size():
			var next_btn: Button = ordered[i + 1]
			_check(b.position.x + b.size.x <= next_btn.position.x,
				"%s: '%s' does not overlap '%s' (right edge %f, next button starts at %f)" % [label, b.text, next_btn.text, b.position.x + b.size.x, next_btn.position.x])

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var chest: Gear = Gear.new()
	chest.display_name = "Old Vest"
	chest.slot = Gear.Slot.CHEST
	chest.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(chest)

	var panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(panel)
	await process_frame

	panel.open_for(inv)
	_check(panel.is_open(), "open_for() shows the panel")

	# --- Break Down ---
	panel.select_breakdown_item_for_test(0)
	panel.press_breakdown_confirm_for_test()
	_check(inv.gear.is_empty(), "confirming Break Down consumes the selected Gear")
	_check(inv.materials.size() == 1 and inv.materials[0].rarity == RarityVisuals.Rarity.RARE and inv.materials[0].quantity == 3, "Break Down grants Rare Scrap x3 (Chest's yield)")

	# --- Craft (deterministic, no Tempering Reels) ---
	panel.select_craft_slot_for_test(Gear.Slot.HEADWEAR)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.COMMON)
	_check(not panel.can_confirm_craft_for_test(), "can't craft Headwear yet -- the party only owns Rare Scrap, Headwear needs Common")

	var common_scrap: CraftingMaterial = CraftingMaterial.new()
	common_scrap.material_type = &"salvage_scrap"
	common_scrap.rarity = RarityVisuals.Rarity.COMMON
	common_scrap.quantity = 1
	inv.give_material(common_scrap)
	_check(panel.can_confirm_craft_for_test(), "can craft Headwear now that 1 Common Scrap is owned (its cost)")

	panel.press_craft_confirm_for_test()
	_check(inv.gear.size() == 1 and inv.gear[0].slot == Gear.Slot.HEADWEAR, "confirming Craft (no Tempering Reels) grants the deterministic Headwear")
	_check(not panel.tempering_panel_for_test().is_open(), "the Tempering Reels panel never opened since it wasn't toggled on")

	# --- Craft with Tempering Reels opted in ---
	var scrap2: CraftingMaterial = CraftingMaterial.new()
	scrap2.material_type = &"salvage_scrap"
	scrap2.rarity = RarityVisuals.Rarity.RARE
	scrap2.quantity = 3
	inv.give_material(scrap2)
	panel.select_craft_slot_for_test(Gear.Slot.CHEST)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	panel.toggle_tempering_for_test()
	panel.press_craft_confirm_for_test()
	_check(panel.tempering_panel_for_test().is_open(), "confirming Craft with Tempering Reels toggled on opens the mini-game instead of granting immediately")
	_check(inv.gear.size() == 1, "no new Gear was granted yet -- the craft is still pending the mini-game's result")

	for i in range(panel.tempering_panel_for_test().reel_count_for_test()):
		panel.tempering_panel_for_test().press_stop_for_test(i)
	panel.tempering_panel_for_test().press_confirm_for_test()
	_check(inv.gear.size() == 2, "confirming the Tempering Reels result finally grants the crafted Chest")
	_check(inv.gear[1].slot == Gear.Slot.CHEST, "the granted Gear is the Chest that was staged")

	# --- Regression (task-7 review, 2026-08-02): toggling Tempering Reels OFF while its mini-game
	# is still open, then re-pressing Craft, must NOT double-grant or corrupt the pending resolution.
	# Before the fix, this took the deterministic branch a second time (granting a second item
	# immediately) and then resolved the original mini-game with the meanwhile-reset (-1, -1)
	# _craft_slot/_craft_rarity.
	var scrap4: CraftingMaterial = CraftingMaterial.new()
	scrap4.material_type = &"salvage_scrap"
	scrap4.rarity = RarityVisuals.Rarity.COMMON
	scrap4.quantity = 5
	inv.give_material(scrap4)

	panel.select_craft_slot_for_test(Gear.Slot.HANDS)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.COMMON)
	panel.toggle_tempering_for_test() # ON
	panel.press_craft_confirm_for_test()
	_check(panel.tempering_panel_for_test().is_open(), "opening Tempering for the Hands craft leaves its mini-game open")

	var gear_count_before_retoggle: int = inv.gear.size()
	var common_scrap_qty_before_retoggle: int = 0
	for m: CraftingMaterial in inv.materials:
		if m.material_type == &"salvage_scrap" and m.rarity == RarityVisuals.Rarity.COMMON:
			common_scrap_qty_before_retoggle = m.quantity

	panel.toggle_tempering_for_test() # OFF, while the mini-game panel is still open
	panel.press_craft_confirm_for_test()
	_check(inv.gear.size() == gear_count_before_retoggle, "re-pressing Craft after toggling Tempering off mid-mini-game must NOT grant a second item")
	var common_scrap_qty_after_retoggle: int = 0
	for m: CraftingMaterial in inv.materials:
		if m.material_type == &"salvage_scrap" and m.rarity == RarityVisuals.Rarity.COMMON:
			common_scrap_qty_after_retoggle = m.quantity
	_check(common_scrap_qty_after_retoggle == common_scrap_qty_before_retoggle, "the re-press must NOT consume Scrap either -- the guard makes it a full no-op")
	_check(panel.tempering_panel_for_test().is_open(), "the original mini-game is still open/resolvable, untouched by the toggle-off re-press")

	for i in range(panel.tempering_panel_for_test().reel_count_for_test()):
		panel.tempering_panel_for_test().press_stop_for_test(i)
	panel.tempering_panel_for_test().press_confirm_for_test()
	_check(inv.gear.size() == gear_count_before_retoggle + 1, "resolving the ORIGINAL mini-game still grants exactly one Gear (the Hands item)")
	_check(inv.gear[inv.gear.size() - 1].slot == Gear.Slot.HANDS, "the granted Gear is the Hands item that was originally staged, not corrupted by the meanwhile-reset _craft_slot/_craft_rarity")

	# --- Regression, safe case (kept alongside the unsafe one above): a repeated Craft press while
	# Tempering Reels stays toggled ON must ALSO be a no-op -- confirms the same guard covers both
	# the "toggle it off" and "just mash the button" ways to re-press Craft mid-mini-game.
	var scrap5: CraftingMaterial = CraftingMaterial.new()
	scrap5.material_type = &"salvage_scrap"
	scrap5.rarity = RarityVisuals.Rarity.RARE
	scrap5.quantity = 10
	inv.give_material(scrap5)

	panel.select_craft_slot_for_test(Gear.Slot.CLOAK)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	panel.toggle_tempering_for_test() # ON (was left OFF by the previous scenario's resolution)
	panel.press_craft_confirm_for_test()
	_check(panel.tempering_panel_for_test().is_open(), "opening Tempering for the Cloak craft leaves its mini-game open")

	var gear_count_before_repress: int = inv.gear.size()
	panel.press_craft_confirm_for_test() # re-press, toggle still ON, mini-game still open
	_check(inv.gear.size() == gear_count_before_repress, "re-pressing Craft with Tempering still ON while its mini-game is open must also be a no-op")
	_check(panel.tempering_panel_for_test().is_open(), "the mini-game is still open after the repeated press")

	for i in range(panel.tempering_panel_for_test().reel_count_for_test()):
		panel.tempering_panel_for_test().press_stop_for_test(i)
	panel.tempering_panel_for_test().press_confirm_for_test()
	_check(inv.gear.size() == gear_count_before_repress + 1, "resolving after the repeated press still grants exactly one Gear (the Cloak item)")
	_check(inv.gear[inv.gear.size() - 1].slot == Gear.Slot.CLOAK, "the granted Gear is the Cloak item that was staged")

	# --- Regression (final-review finding, 2026-08-02): a full Bag must disable Craft with a
	# visible message instead of silently rendering Craft as pressable and doing nothing.
	var full_inv: PartyInventory = PartyInventory.new()
	var full_scrap: CraftingMaterial = CraftingMaterial.new()
	full_scrap.material_type = &"salvage_scrap"
	full_scrap.rarity = RarityVisuals.Rarity.COMMON
	full_scrap.quantity = 10
	full_inv.give_material(full_scrap)
	for i in range(full_inv.bag_capacity()):
		var filler: Gear = Gear.new()
		filler.display_name = "Filler %d" % i
		filler.slot = Gear.Slot.HEADWEAR
		filler.rarity = RarityVisuals.Rarity.COMMON
		full_inv.gear.append(filler)
	_check(not full_inv.can_add_to_bag(), "test setup: the Bag is genuinely full")

	var full_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(full_panel)
	await process_frame
	full_panel.open_for(full_inv)
	full_panel.select_craft_slot_for_test(Gear.Slot.HANDS)
	full_panel.select_craft_rarity_for_test(RarityVisuals.Rarity.COMMON)
	_check(not full_panel.can_confirm_craft_for_test(), "Craft is disabled when the Bag is full even though Scrap is sufficient")
	_check(full_panel.craft_message_for_test() == "Bag full", "the message row explains WHY Craft is disabled ('Bag full', not 'Insufficient Scrap')")

	var gear_count_before_disabled_press: int = full_inv.gear.size()
	full_panel.press_craft_confirm_for_test()
	_check(full_inv.gear.size() == gear_count_before_disabled_press, "pressing Craft while disabled by Bag-full is a genuine no-op")

	# --- Regression (final-review finding, 2026-08-02): if the Bag fills up (via some unrelated
	# action) WHILE a Tempering Reels mini-game is still open, resolving it must show a message
	# instead of silently discarding the whole played-out result -- this is the worse of the two
	# silent-failure paths, since the player just finished playing a mini-game for nothing.
	var mid_inv: PartyInventory = PartyInventory.new()
	var mid_scrap: CraftingMaterial = CraftingMaterial.new()
	mid_scrap.material_type = &"salvage_scrap"
	mid_scrap.rarity = RarityVisuals.Rarity.RARE
	mid_scrap.quantity = 10
	mid_inv.give_material(mid_scrap)

	var mid_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(mid_panel)
	await process_frame
	mid_panel.open_for(mid_inv)
	mid_panel.select_craft_slot_for_test(Gear.Slot.CHEST)
	mid_panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	mid_panel.toggle_tempering_for_test()
	mid_panel.press_craft_confirm_for_test()
	_check(mid_panel.tempering_panel_for_test().is_open(), "the mini-game opens while the Bag still has room")

	# Fill the Bag to capacity WHILE the mini-game is still open/unresolved.
	for i in range(mid_inv.bag_capacity()):
		var filler2: Gear = Gear.new()
		filler2.display_name = "Filler %d" % i
		filler2.slot = Gear.Slot.HANDS
		filler2.rarity = RarityVisuals.Rarity.COMMON
		mid_inv.gear.append(filler2)
	var gear_count_before_resolve: int = mid_inv.gear.size()

	for i in range(mid_panel.tempering_panel_for_test().reel_count_for_test()):
		mid_panel.tempering_panel_for_test().press_stop_for_test(i)
	mid_panel.tempering_panel_for_test().press_confirm_for_test()

	_check(mid_inv.gear.size() == gear_count_before_resolve, "the crafted item is NOT granted when the Bag is full at resolve time")
	_check(not mid_panel.tempering_panel_for_test().is_open(), "the mini-game panel still closes even though the craft it resolves into fails")
	_check(mid_panel.craft_message_for_test() == "Bag full -- the crafted item was lost.", "resolving Tempering Reels into a full Bag shows a message instead of silently discarding the result")

	# --- Layout regression (final-review finding, 2026-08-02): a long Break Down list (15+ Gear
	# items -- easily reachable via loot/the general store) must not visually collide with the
	# Craft section. Mirrors tests/test_team_up_panel_center_band.gd's pairwise Rect2.intersects()
	# regression style.
	var big_inv: PartyInventory = PartyInventory.new()
	for i in range(15):
		var junk: Gear = Gear.new()
		junk.display_name = "Junk %d" % i
		junk.slot = Gear.Slot.HEADWEAR
		junk.rarity = RarityVisuals.Rarity.COMMON
		big_inv.gear.append(junk)

	var big_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(big_panel)
	await process_frame
	big_panel.open_for(big_inv)

	_check(big_panel.breakdown_row_count_for_test() == ProfessionsMenuPanel.MAX_VISIBLE_BREAKDOWN_ROWS,
		"the Break Down list caps its visible rows even with 15 Gear items owned (got %d)" % big_panel.breakdown_row_count_for_test())

	var craft_slot_rect: Rect2 = Rect2(
		big_panel._slot_buttons[Gear.Slot.HEADWEAR].position,
		big_panel._slot_buttons[Gear.Slot.HEADWEAR].custom_minimum_size)
	var craft_rarity_rect: Rect2 = Rect2(
		big_panel._rarity_buttons[RarityVisuals.Rarity.COMMON].position,
		big_panel._rarity_buttons[RarityVisuals.Rarity.COMMON].custom_minimum_size)
	var last_breakdown_row: Button = big_panel._breakdown_buttons[big_panel._breakdown_buttons.size() - 1]
	var last_row_rect: Rect2 = Rect2(last_breakdown_row.position, last_breakdown_row.custom_minimum_size)
	var confirm_rect: Rect2 = Rect2(big_panel._breakdown_confirm_button.position, big_panel._breakdown_confirm_button.custom_minimum_size)

	_check(not last_row_rect.intersects(craft_slot_rect), "the last visible Break Down row does not overlap the Craft section's slot row")
	_check(not last_row_rect.intersects(craft_rarity_rect), "the last visible Break Down row does not overlap the Craft section's rarity row")
	_check(not confirm_rect.intersects(craft_slot_rect), "the Salvage confirm button does not overlap the Craft section's slot row")

	# --- Cooking section (task 7) ---
	var cook_inv: PartyInventory = PartyInventory.new()
	var berries: CraftingMaterial = CraftingMaterial.new()
	berries.material_type = &"forage_herb"
	berries.rarity = RarityVisuals.Rarity.COMMON
	berries.quantity = 2
	cook_inv.give_material(berries)

	var cook_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(cook_panel)
	await process_frame

	cook_panel.open_for(cook_inv)
	_check(cook_panel.active_section_for_test() == &"salvaging", "open_for() always resets to the Salvaging tab")

	cook_panel.switch_to_cooking_for_test()
	_check(cook_panel.active_section_for_test() == &"cooking", "switch_to_cooking_for_test() switches the active tab")

	cook_panel.select_cooking_recipe_for_test(&"wildberry_jam")
	cook_panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	_check(cook_panel.can_confirm_cook_for_test(), "can cook Wildberry Jam with 2 Common Wild Berries owned")

	cook_panel.press_cook_confirm_for_test()
	_check(cook_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON) != null, "confirming Cook (no Second Helping) grants the deterministic Jam")
	_check(not cook_panel.second_helping_panel_for_test().is_open(), "the Second Helping panel never opened since it wasn't toggled on")

	var more_berries: CraftingMaterial = CraftingMaterial.new()
	more_berries.material_type = &"forage_herb"
	more_berries.rarity = RarityVisuals.Rarity.COMMON
	more_berries.quantity = 2
	cook_inv.give_material(more_berries)
	cook_panel.select_cooking_recipe_for_test(&"wildberry_jam")
	cook_panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	cook_panel.toggle_second_helping_for_test()
	cook_panel.press_cook_confirm_for_test()
	_check(cook_panel.second_helping_panel_for_test().is_open(), "confirming Cook with Second Helping toggled on opens the mini-game instead of granting immediately")

	cook_panel.second_helping_panel_for_test().advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	cook_panel.second_helping_panel_for_test().press_bank_for_test()
	var final_jam: ConsumableItem = cook_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON)
	_check(final_jam != null and final_jam.quantity >= 2, "banking the Second Helping result grants at least the deterministic quantity (base 1 from the first cook + at least 1 more from the second, plus any bonus)")

	# --- Regression (mirrors the Salvaging re-press guard, task 7): toggling Second Helping OFF while
	# its mini-game is still open, then re-pressing Cook, must NOT double-grant or corrupt the pending
	# resolution.
	var more_berries2: CraftingMaterial = CraftingMaterial.new()
	more_berries2.material_type = &"forage_herb"
	more_berries2.rarity = RarityVisuals.Rarity.COMMON
	more_berries2.quantity = 2
	cook_inv.give_material(more_berries2)

	cook_panel.select_cooking_recipe_for_test(&"wildberry_jam")
	cook_panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	cook_panel.toggle_second_helping_for_test() # ON
	cook_panel.press_cook_confirm_for_test()
	_check(cook_panel.second_helping_panel_for_test().is_open(), "opening Second Helping for another Jam cook leaves its mini-game open")

	var jam_qty_before_retoggle: int = cook_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON).quantity
	cook_panel.toggle_second_helping_for_test() # OFF, while the mini-game panel is still open
	cook_panel.press_cook_confirm_for_test()
	var jam_qty_after_retoggle: int = cook_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON).quantity
	_check(jam_qty_after_retoggle == jam_qty_before_retoggle, "re-pressing Cook after toggling Second Helping off mid-mini-game must NOT grant a second dish")
	_check(cook_panel.second_helping_panel_for_test().is_open(), "the original mini-game is still open/resolvable, untouched by the toggle-off re-press")

	cook_panel.second_helping_panel_for_test().advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	cook_panel.second_helping_panel_for_test().press_bank_for_test()
	var jam_qty_after_resolve: int = cook_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON).quantity
	_check(jam_qty_after_resolve > jam_qty_before_retoggle, "resolving the ORIGINAL mini-game still grants the Jam, not corrupted by the meanwhile-reset recipe/rarity")

	# --- Regression (task 7, mirrors the Salvaging "Bag full disables Craft" finding): a full Bag
	# must disable Cook with a visible message when the party has no pre-existing stack of the output
	# dish/rarity to merge into (a genuinely new stack would need bag room).
	var full_cook_inv: PartyInventory = PartyInventory.new()
	var full_cook_berries: CraftingMaterial = CraftingMaterial.new()
	full_cook_berries.material_type = &"forage_herb"
	full_cook_berries.rarity = RarityVisuals.Rarity.COMMON
	full_cook_berries.quantity = 10
	full_cook_inv.give_material(full_cook_berries)
	for i in range(full_cook_inv.bag_capacity()):
		var cook_filler: Gear = Gear.new()
		cook_filler.display_name = "Filler %d" % i
		cook_filler.slot = Gear.Slot.HEADWEAR
		cook_filler.rarity = RarityVisuals.Rarity.COMMON
		full_cook_inv.gear.append(cook_filler)
	_check(not full_cook_inv.can_add_to_bag(), "test setup: the Bag is genuinely full")

	var full_cook_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(full_cook_panel)
	await process_frame
	full_cook_panel.open_for(full_cook_inv)
	full_cook_panel.switch_to_cooking_for_test()
	full_cook_panel.select_cooking_recipe_for_test(&"wildberry_jam")
	full_cook_panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	_check(not full_cook_panel.can_confirm_cook_for_test(), "Cook is disabled when the Bag is full and no matching Jam stack already exists to merge into")
	_check(full_cook_panel.cook_message_for_test() == "Bag full", "the message row explains WHY Cook is disabled ('Bag full', not 'Insufficient ingredients')")

	var items_count_before_disabled_press: int = full_cook_inv.items.size()
	full_cook_panel.press_cook_confirm_for_test()
	_check(full_cook_inv.items.size() == items_count_before_disabled_press, "pressing Cook while disabled by Bag-full is a genuine no-op")

	# --- Regression (task 7): a full Bag must NOT block cooking more of a dish/rarity the party
	# already holds a stack of, since try_give_item() merges into an existing stack regardless of
	# capacity.
	var existing_jam: ConsumableItem = ConsumableItem.new()
	existing_jam.item_type = &"wildberry_jam"
	existing_jam.display_name = "Wildberry Jam"
	existing_jam.rarity = RarityVisuals.Rarity.COMMON
	existing_jam.quantity = 1
	full_cook_inv.items.append(existing_jam)
	_check(full_cook_panel.can_confirm_cook_for_test(), "Cook is enabled on a full Bag once the party already holds a matching Jam stack to merge into")
	full_cook_panel.press_cook_confirm_for_test()
	_check(existing_jam.quantity == 2, "confirming Cook merges into the existing stack even though the Bag is full")

	# Task 1 (2026-08-07 professions-playtest-fixes): Craft slot buttons must show the bare slot
	# name, not the full crafted-item display name -- "Handcrafted Headwear" doesn't fit the
	# button's width and was the actual cause of the visible overlap bug. This also doubles as the
	# discoverability fix: a slot button reading "Headwear" is unambiguously a slot choice.
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.HEADWEAR) == "Headwear", "slot_label maps HEADWEAR to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.CLOAK) == "Cloak", "slot_label maps CLOAK to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.CHEST) == "Chest", "slot_label maps CHEST to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.HANDS) == "Hands", "slot_label maps HANDS to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.CHARM) == "Charm", "slot_label maps CHARM to the bare slot name")

	# Task 2 (2026-08-07 professions-playtest-fixes): an embedded read-only inventory strip shows
	# the party's current Materials + Gear so the player doesn't have to open Inventory separately
	# to see what they have to work with while Professions is open.
	var strip_inv: PartyInventory = PartyInventory.new()
	var scrap: CraftingMaterial = CraftingMaterial.new()
	scrap.material_type = &"salvage_scrap"
	scrap.display_name = "Salvage Scrap"
	scrap.rarity = RarityVisuals.Rarity.COMMON
	scrap.quantity = 3
	strip_inv.materials = [scrap]
	var cloak: Gear = Gear.new()
	cloak.display_name = "Traveler's Cloak"
	cloak.slot = Gear.Slot.CLOAK
	cloak.rarity = RarityVisuals.Rarity.UNCOMMON
	strip_inv.gear = [cloak]

	var strip_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(strip_panel)
	await process_frame
	strip_panel.open_for(strip_inv)
	_check(strip_panel.inventory_strip_row_count_for_test() == 2, "inventory strip shows 1 material row + 1 gear row (got %d)" % strip_panel.inventory_strip_row_count_for_test())
	strip_panel.queue_free()

	# Task 3 (2026-08-07 professions-playtest-fixes): hover tooltips show each recipe's actual
	# required inputs so the player doesn't have to guess or check the design doc.
	var tooltip_inv: PartyInventory = PartyInventory.new()
	var tooltip_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(tooltip_panel)
	await process_frame
	tooltip_panel.open_for(tooltip_inv)

	# Before any rarity is picked, the slot tooltip is a generic prompt rather than a wrong number.
	_check(tooltip_panel.craft_slot_tooltip_for_test(Gear.Slot.CHEST).find("rarity") != -1, "Chest slot tooltip prompts for a rarity before one is picked")

	tooltip_panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	_check(tooltip_panel.craft_slot_tooltip_for_test(Gear.Slot.CHEST) == "Costs 3 Salvage Scrap (Rare).", "Chest slot tooltip shows the correct Scrap cost once a rarity is picked (got: %s)" % tooltip_panel.craft_slot_tooltip_for_test(Gear.Slot.CHEST))
	_check(tooltip_panel.craft_rarity_tooltip_for_test(RarityVisuals.Rarity.RARE).find("Select a slot") != -1, "Rarity tooltip prompts for a slot before one is picked")

	tooltip_panel.select_craft_slot_for_test(Gear.Slot.CLOAK)
	_check(tooltip_panel.craft_rarity_tooltip_for_test(RarityVisuals.Rarity.EPIC) == "Costs 2 Salvage Scrap (Epic).", "Cloak rarity tooltip shows the correct Scrap cost once a slot is picked (got: %s)" % tooltip_panel.craft_rarity_tooltip_for_test(RarityVisuals.Rarity.EPIC))

	tooltip_panel.switch_to_cooking_for_test()
	_check(tooltip_panel.cooking_recipe_tooltip_for_test(&"wildberry_jam") == "Requires 2x Wild Berries (any one rarity).", "Wildberry Jam tooltip shows its real material requirement (got: %s)" % tooltip_panel.cooking_recipe_tooltip_for_test(&"wildberry_jam"))
	_check(tooltip_panel.cooking_recipe_tooltip_for_test(&"roasted_fish") == "Requires 1x Minnow, Freshwater Fish, or Prize Bass (any one rarity).", "Roasted Fish tooltip shows its real material requirement (got: %s)" % tooltip_panel.cooking_recipe_tooltip_for_test(&"roasted_fish"))
	tooltip_panel.queue_free()

	# Task 5 (2026-08-07 professions-playtest-fixes): Break Down / Craft / Cook each report one
	# line through whatever log_fn the panel wires up, tagged CATEGORY_CRAFTING.
	var logged: Array = []
	var log_inv: PartyInventory = PartyInventory.new()
	var log_cloak: Gear = Gear.new()
	log_cloak.display_name = "Traveler's Cloak"
	log_cloak.slot = Gear.Slot.CLOAK
	log_cloak.rarity = RarityVisuals.Rarity.UNCOMMON
	log_inv.gear = [log_cloak]

	var log_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(log_panel)
	await process_frame
	log_panel.set_log_fn_for_test(func(line: String) -> void: logged.append(line))
	log_panel.open_for(log_inv)

	log_panel.select_breakdown_item_for_test(0)
	log_panel.press_breakdown_confirm_for_test()
	_check(logged.size() == 1, "Break Down logs exactly one line (got %d)" % logged.size())
	_check(logged[0].find("Traveler's Cloak") != -1 and logged[0].find("Salvage Scrap") != -1, "the logged Break Down line names both the salvaged item and the material it produced (got: %s)" % (logged[0] if logged.size() > 0 else "<none>"))

	log_panel.select_craft_slot_for_test(Gear.Slot.CLOAK)
	log_panel.select_craft_rarity_for_test(RarityVisuals.Rarity.UNCOMMON)
	log_panel.press_craft_confirm_for_test()
	_check(logged.size() == 2, "Craft logs exactly one more line (got %d total)" % logged.size())
	_check(logged[1].find("Handcrafted Cloak") != -1, "the logged Craft line names the crafted item (got: %s)" % (logged[1] if logged.size() > 1 else "<none>"))
	log_panel.queue_free()

	# Task 1 (2026-08-08 professions-playtest-round2), REWRITTEN by that plan's final whole-branch
	# review: the 5 Craft slot buttons and both rarity rows (Craft's and Cooking's) must fit within
	# PANEL_W *and* not overlap each other. The previous version of this block asserted on
	# `custom_minimum_size.x` (a floor, not the rendered width) and only checked the panel's own right
	# edge, so it printed `ok` while "Uncommon" overlapped "Rare" by 15px and "Headwear" overlapped
	# "Cloak" by 3px. See _check_row_no_overlap()'s doc comment above.
	var fit_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(fit_panel)
	await process_frame
	fit_panel.open_for(PartyInventory.new())
	await process_frame
	_check_row_no_overlap(fit_panel._slot_buttons, ProfessionsMenuPanel.ARMOR_SLOTS, "Craft slot row (nothing selected)")
	_check_row_no_overlap(fit_panel._rarity_buttons, ProfessionsMenuPanel.RARITIES, "Craft rarity row (nothing selected)")

	# The SELECTED state is exactly what the first fix missed: appending "  ✓" made the selected
	# button's text -- and therefore its rendered width -- longer than the unselected one, so a row
	# that fit while nothing was picked overlapped the moment the player picked something. Selection
	# is a modulate tint now, so re-measure with the two widest labels selected.
	fit_panel.select_craft_slot_for_test(Gear.Slot.HEADWEAR)
	fit_panel.select_craft_rarity_for_test(RarityVisuals.Rarity.UNCOMMON)
	await process_frame
	_check(fit_panel._slot_buttons[Gear.Slot.HEADWEAR].text == "Headwear",
		"selecting a Craft slot does not lengthen its button's text (got '%s')" % fit_panel._slot_buttons[Gear.Slot.HEADWEAR].text)
	_check(fit_panel._slot_buttons[Gear.Slot.HEADWEAR].modulate == ProfessionsMenuPanel.SELECTED_TINT,
		"the selected Craft slot is indicated by a tint instead of a text suffix")
	_check(fit_panel._slot_buttons[Gear.Slot.CLOAK].modulate == Color.WHITE, "an unselected Craft slot is untinted")
	_check_row_no_overlap(fit_panel._slot_buttons, ProfessionsMenuPanel.ARMOR_SLOTS, "Craft slot row ('Headwear' selected)")
	_check_row_no_overlap(fit_panel._rarity_buttons, ProfessionsMenuPanel.RARITIES, "Craft rarity row ('Uncommon' selected)")

	fit_panel.switch_to_cooking_for_test()
	await process_frame
	_check_row_no_overlap(fit_panel._cooking_rarity_buttons, ProfessionsMenuPanel.RARITIES, "Cooking rarity row (nothing selected)")
	fit_panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.LEGENDARY)
	await process_frame
	_check(fit_panel._cooking_rarity_buttons[RarityVisuals.Rarity.LEGENDARY].text == "Legendary",
		"selecting a Cooking rarity does not lengthen its button's text (got '%s')" % fit_panel._cooking_rarity_buttons[RarityVisuals.Rarity.LEGENDARY].text)
	_check_row_no_overlap(fit_panel._cooking_rarity_buttons, ProfessionsMenuPanel.RARITIES, "Cooking rarity row ('Legendary' selected)")
	fit_panel.queue_free()

	# The panel recenters itself on the viewport after every rebuild, tracking its own actual
	# (dynamic) size -- but NEVER past the top-left corner of the screen. Also rewritten by the
	# final review: the previous version opened the panel with an EMPTY PartyInventory (a short panel
	# that never reproduces the bug) and compared `position` against the exact same expression the
	# implementation itself computes, so it could not fail regardless of what the implementation did.
	# These assertions are absolute and implementation-independent instead.
	var center_inv: PartyInventory = PartyInventory.new()
	for i in range(4):   # mirrors InventoryDemoSetup's real demo party: 4 Bag Gear items
		var demo_gear: Gear = Gear.new()
		demo_gear.display_name = "Demo Gear %d" % i
		demo_gear.slot = Gear.Slot.HEADWEAR
		demo_gear.rarity = RarityVisuals.Rarity.COMMON
		center_inv.gear.append(demo_gear)

	var center_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(center_panel)
	await process_frame
	center_panel.open_for(center_inv)
	_check(center_panel.position.y >= 0.0,
		"a panel taller than the window is never pushed off the TOP of the screen (Salvaging tab, realistic 4-Gear inventory: y=%f)" % center_panel.position.y)
	_check(center_panel.position.x >= 0.0, "...nor off the LEFT edge (x=%f)" % center_panel.position.x)
	center_panel.switch_to_cooking_for_test()
	_check(center_panel.position.y >= 0.0, "the same holds after switching to the Cooking tab (y=%f)" % center_panel.position.y)
	center_panel.queue_free()

	# ...and the same, measured against the game's REAL window size. The headless SceneTree's own root
	# viewport is 64x64 and refuses to be resized, so any assertion phrased in terms of it is checking
	# against a 64px-tall screen. A SubViewport sized to the real 1600x900 window is what actually
	# reproduces the playtest-visible bug: with the demo party's 4 Bag Gear items the Salvaging tab is
	# 460x614 scaled 2x = 1228px tall, and the old unclamped centering put it at y=-164 with the
	# Cooking tab (the only way to switch tabs at all) at screen y=-140 -- entirely unreachable.
	var real_vp := SubViewport.new()
	real_vp.size = Vector2i(1600, 900)
	get_root().add_child(real_vp)
	await process_frame

	var tall_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	real_vp.add_child(tall_panel)
	await process_frame
	tall_panel.open_for(center_inv)
	await process_frame
	_check(tall_panel.get_viewport_rect().size == Vector2(1600.0, 900.0),
		"test setup: the panel really is laid out against a 1600x900 viewport (got %s)" % tall_panel.get_viewport_rect().size)
	_check(tall_panel.size.y * tall_panel.scale.y > 900.0,
		"test setup: a realistic 4-Gear inventory really does make the panel taller than the window (%f px)" % (tall_panel.size.y * tall_panel.scale.y))
	var cooking_tab_screen_y: float = tall_panel.position.y + tall_panel._tab_buttons[&"cooking"].position.y * tall_panel.scale.y
	_check(cooking_tab_screen_y >= 0.0,
		"the Cooking tab stays on-screen even when the panel is taller than the window (screen y=%f)" % cooking_tab_screen_y)
	_check(tall_panel.position.y == ProfessionsMenuPanel.TOP_MARGIN,
		"an over-tall panel anchors at TOP_MARGIN instead of centering (y=%f)" % tall_panel.position.y)

	var short_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	real_vp.add_child(short_panel)
	await process_frame
	short_panel.open_for(PartyInventory.new())
	await process_frame
	var short_h: float = short_panel.size.y * short_panel.scale.y
	_check(short_h <= 900.0, "test setup: an empty inventory really does fit the window (%f px)" % short_h)
	var top_gap: float = short_panel.position.y
	var bottom_gap: float = 900.0 - (short_panel.position.y + short_h)
	_check(absf(top_gap - bottom_gap) <= 1.0,
		"a panel that FITS is still genuinely centered -- equal gaps above and below (top %f, bottom %f)" % [top_gap, bottom_gap])
	var left_gap: float = short_panel.position.x
	var right_gap: float = 1600.0 - (short_panel.position.x + short_panel.size.x * short_panel.scale.x)
	_check(absf(left_gap - right_gap) <= 1.0,
		"...and horizontally centered too (left %f, right %f)" % [left_gap, right_gap])
	tall_panel.queue_free()
	short_panel.queue_free()
	real_vp.queue_free()

	# Task 2 (2026-08-08 professions-playtest-round2): the embedded strip is scoped per profession --
	# Salvaging shows only Scrap materials (not Foraging/Fishing ingredients) + all Bag Gear; Cooking
	# shows only its own ingredient materials + the food it can produce, and drops Gear entirely.
	var scoped_inv: PartyInventory = PartyInventory.new()
	var scrap3: CraftingMaterial = CraftingMaterial.new()
	scrap3.material_type = &"salvage_scrap"
	scrap3.display_name = "Salvage Scrap"
	scrap3.rarity = RarityVisuals.Rarity.COMMON
	scrap3.quantity = 2
	var berries2: CraftingMaterial = CraftingMaterial.new()
	berries2.material_type = &"forage_herb"
	berries2.display_name = "Wild Berries"
	berries2.rarity = RarityVisuals.Rarity.COMMON
	berries2.quantity = 5
	scoped_inv.materials = [scrap3, berries2]
	var scoped_gear: Gear = Gear.new()
	scoped_gear.display_name = "Old Boots"
	scoped_gear.slot = Gear.Slot.HANDS
	scoped_gear.rarity = RarityVisuals.Rarity.COMMON
	scoped_inv.gear = [scoped_gear]
	var jam_item: ConsumableItem = ConsumableItem.new()
	jam_item.item_type = &"wildberry_jam"
	jam_item.display_name = "Wildberry Jam"
	jam_item.rarity = RarityVisuals.Rarity.COMMON
	jam_item.quantity = 1
	var potion_item: ConsumableItem = ConsumableItem.new()
	potion_item.item_type = &"healing_potion"
	potion_item.display_name = "Healing Potion"
	potion_item.rarity = RarityVisuals.Rarity.COMMON
	potion_item.quantity = 1
	scoped_inv.items = [jam_item, potion_item]

	var scoped_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(scoped_panel)
	await process_frame
	scoped_panel.open_for(scoped_inv)
	var salvaging_strip_text: String = scoped_panel.inventory_strip_text_for_test()
	_check(salvaging_strip_text.find("Salvage Scrap") != -1, "Salvaging strip shows Scrap")
	_check(salvaging_strip_text.find("Old Boots") != -1, "Salvaging strip shows all Bag Gear")
	_check(salvaging_strip_text.find("Wild Berries") == -1, "Salvaging strip hides Foraging/Fishing materials")
	_check(scoped_panel.inventory_strip_row_count_for_test() == 2, "Salvaging strip shows only Scrap (1) + Gear (1), hiding Wild Berries (got %d)" % scoped_panel.inventory_strip_row_count_for_test())

	scoped_panel.switch_to_cooking_for_test()
	var cooking_strip_text: String = scoped_panel.inventory_strip_text_for_test()
	_check(cooking_strip_text.find("Wild Berries") != -1, "Cooking strip shows its own ingredient materials")
	_check(cooking_strip_text.find("Wildberry Jam") != -1, "Cooking strip shows the food it can produce")
	_check(cooking_strip_text.find("Salvage Scrap") == -1, "Cooking strip hides Salvaging's Scrap")
	_check(cooking_strip_text.find("Old Boots") == -1, "Cooking strip drops the Gear section entirely")
	_check(cooking_strip_text.find("Healing Potion") == -1, "Cooking strip hides consumables it can't itself produce")
	_check(scoped_panel.inventory_strip_row_count_for_test() == 2, "Cooking strip shows only Wild Berries (1) + Wildberry Jam (1) (got %d)" % scoped_panel.inventory_strip_row_count_for_test())
	scoped_panel.queue_free()

	print("ok ProfessionsMenuPanel (Salvaging + Cooking) smoke test complete")
	quit()
