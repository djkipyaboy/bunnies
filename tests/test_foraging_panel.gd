extends SceneTree

## ForagingPanel: view over ForagingMinigame (2026-08-01 gathering-profession-minigames spec
## section 2), now with a presentation-only spin animation over a shared ReelStripWidget
## (2026-08-02 gathering-playtest-fixes spec section 3). The model still picks current_tier
## instantly and randomly -- the spin only decides how long the reveal takes, never what it lands
## on. Mirrors tests/test_random_encounter_panel.gd's SceneTree/_initialize()/press_*_for_test
## structure.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

## Fast-forwards a panel's spin all the way to landing, regardless of how much time is actually
## left on it.
func _land(panel: ForagingPanel) -> void:
	panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()

	var panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(panel)
	await process_frame

	_check(panel.scale == Vector2(2.0, 2.0), "the panel is scaled 2x for legibility (spec section 4)")

	panel.open_for(&"forage_herb", "Wild Berries", 1, inv)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visible")
	_check(panel.is_spinning_for_test(), "open_for immediately starts a spin")

	panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS * 0.5)
	_check(panel.is_spinning_for_test(), "advancing less than the full spin duration keeps spinning")

	_land(panel)
	_check(not panel.is_spinning_for_test(), "advancing past the full spin duration lands the spin")
	# Compares against the shortened reel-face label (Task 10, 2026-08-07 professions-playtest-fixes),
	# not the tier's raw full name -- this assertion draws a REAL random tier (no tiers_override), so
	# without routing through _reel_face_label() here, roughly 1-in-4 runs land on "Bumper Crop" and
	# spuriously fail (the cell shows the shortened "Bumper", the raw name is the un-shortened full
	# string). Found via a real regression sweep hitting exactly that ~25% chance.
	_check(panel.reel_strip_for_test().cell_text_for_test(&"current") == ForagingPanel._reel_face_label(panel.current_tier_name_for_test()),
		"the landed strip shows the tier the model actually picked, not a coincidence of timing")
	_check(panel.reel_strip_for_test().cell_color_for_test(&"current") == ForagingPanel._color_for_tier_name(panel.current_tier_name_for_test()),
		"the landed strip's current cell color matches the tier's mapped RarityVisuals color")

	# Prove the landing genuinely tracks the model's pick (not always the same visual index) by
	# rigging two DIFFERENT single-tier pools and confirming each lands on ITS OWN tier.
	var meager_only: Array[Dictionary] = [{"name": "Meager", "quantity_multiplier": 1, "quality_bonus": 0}]
	var meager_panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(meager_panel)
	await process_frame
	meager_panel.open_for(&"forage_herb", "Wild Berries", 1, inv, meager_only)
	_land(meager_panel)
	_check(meager_panel.reel_strip_for_test().cell_text_for_test(&"current") == "Meager", "a rigged Meager-only pool lands the strip on Meager")
	meager_panel.free()

	var bumper_only: Array[Dictionary] = [{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}]
	var bumper_panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(bumper_panel)
	await process_frame
	bumper_panel.open_for(&"forage_herb", "Wild Berries", 1, inv, bumper_only)
	_land(bumper_panel)
	# Cell text is the Task 10 (2026-08-07 professions-playtest-fixes) shortened reel-face label
	# ("Bumper", not "Bumper Crop") -- this pre-existing assertion predates that shortening and was
	# left stale (still checking the full name) when Task 10 landed. current_tier_name_for_test()
	# elsewhere in this file already proves the underlying tier's full name is untouched.
	_check(bumper_panel.reel_strip_for_test().cell_text_for_test(&"current") == "Bumper", "a rigged Bumper Crop-only pool lands the strip on the shortened \"Bumper\" cell label (a DIFFERENT tier than the previous case)")
	bumper_panel.free()

	# --- Button disabling through the spin, and mid-spin presses are no-ops ---
	panel.open_for(&"forage_herb", "Wild Berries", 1, inv, meager_only)
	_check(panel.is_spinning_for_test(), "re-opening starts a fresh spin")
	var shakes_before: int = panel.shakes_remaining_for_test()
	panel.press_shake_for_test()   # a real click can't reach this (disabled), but a test-hook press must also no-op
	_check(panel.shakes_remaining_for_test() == shakes_before, "pressing Shake mid-spin is a no-op (does not consume a shake)")
	_land(panel)

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

	# Re-opening for a second node proves state resets cleanly between uses, and that shaking
	# AFTER landing genuinely consumes a shake (proving the earlier mid-spin no-op didn't leave
	# shaking permanently broken).
	panel.open_for(&"fish_meat", "Freshwater Fish", 1, inv)
	_land(panel)
	_check(panel.visible, "re-opening shows the panel again")
	var shakes_before2: int = panel.shakes_remaining_for_test()
	panel.press_shake_for_test()
	_check(panel.shakes_remaining_for_test() == shakes_before2 - 1, "shaking after landing genuinely consumes a shake")
	_land(panel)
	panel.press_bank_for_test()
	_check(inv.materials.size() == 2, "a second, independent bank grants a second stacked-or-separate material entry")
	_check(completed_events.size() == 2, "foraging_completed fires again on the second bank")

	# tiers_override forces a deterministic Bumper Crop bank, proving quality_tier actually
	# propagates from ForagingMinigame's outcome onto the granted CraftingMaterial.
	var inv2: PartyInventory = PartyInventory.new()
	panel.open_for(&"forage_herb", "Wild Berries", 3, inv2, bumper_only)
	_land(panel)
	panel.press_bank_for_test()
	var bumper_material: CraftingMaterial = inv2.materials[0]
	_check(bumper_material.quantity == 6, "a x2 Bumper Crop bank on a base quantity of 3 grants 6 (3 * 2)")
	_check(bumper_material.quality_tier == 1, "a Bumper Crop bank stamps quality_tier == 1 onto the granted material")

	_check(ForagingPanel._color_for_tier_name("Meager") == RarityVisuals.color(RarityVisuals.Rarity.COMMON), "Meager maps to the Common (white) color")
	_check(ForagingPanel._color_for_tier_name("Modest") == RarityVisuals.color(RarityVisuals.Rarity.UNCOMMON), "Modest maps to the Uncommon (green) color")
	_check(ForagingPanel._color_for_tier_name("Bountiful") == RarityVisuals.color(RarityVisuals.Rarity.RARE), "Bountiful maps to the Rare (blue) color")
	_check(ForagingPanel._color_for_tier_name("Bumper Crop") == RarityVisuals.color(RarityVisuals.Rarity.EPIC), "Bumper Crop maps to the Epic (purple) color")
	_check(ForagingPanel._color_for_tier_name("Not A Real Tier") == Color.WHITE, "an unrecognized tier name falls back to white rather than erroring")

	# Task 10 (2026-08-07 professions-playtest-fixes): "Bumper Crop" is too long to fit
	# ReelStripWidget's CELL_W, so the reel FACE specifically shows the shortened "Bumper" --
	# everything else (the result description, current_tier_name_for_test()) keeps the full name.
	var task10_panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(task10_panel)
	await process_frame
	var bumper_tiers: Array[Dictionary] = [{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}]
	task10_panel.open_for(&"forage_herb", "Wild Berries", 1, PartyInventory.new(), bumper_tiers)
	task10_panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)
	_check(task10_panel.current_tier_name_for_test() == "Bumper Crop", "the underlying tier's full name is untouched")
	_check(task10_panel.reel_strip_for_test().cell_text_for_test(&"current") == "Bumper", "the reel-face CELL specifically shows the shortened \"Bumper\", not the full \"Bumper Crop\"")
	task10_panel.queue_free()

	panel.free()
	quit()
