extends SceneTree

## End-to-end proof that Salvaging + Cooking work together through the real town_demo.tscn scene:
## salvage a piece of gear -> craft a replacement (with Tempering Reels) -> cook a recipe (with
## Second Helping) -> the cooked food is usable via the SAME Item Reel plumbing Healing Potion uses.
## (2026-08-02 salvaging-and-cooking professions design, full feature.)
##
## Uses _initialize()/await process_frame (mirroring tests/test_town_demo_old_well.gd and
## tests/test_town_demo_professions.gd) rather than the plan's own literal _init() snippet --
## town_demo.gd's _ready() (which builds _professions_panel and _party_inventory) hasn't run yet
## immediately after add_child() inside a plain _init(); confirmed empirically (RED: "Invalid access
## to property or key 'gear' on a base object of type 'Nil'" at the _party_inventory read) before
## switching to this project's already-established _initialize() convention for driving this exact
## scene end-to-end.

var _failures: int = 0

## Tracks failures and returns a nonzero process exit via quit(_failures) below -- this project has
## repeatedly documented test files whose own internal pass/fail tracking never propagates to the
## process exit code (test_adventuring_board_panel.gd, test_overworld_demo_npcs.gd, and others,
## memory `silent-script-error-exits-zero-gotcha`); the plan's own literal snippet's bare _check()
## (print-only, no counter) plus a bare quit() would have made this closing end-to-end test exit-code
## blind too, contradicting its own doc comment's claim to mirror test_town_demo_old_well.gd (which
## DOES track failures and calls quit(_failures)).
func _check(cond: bool, label: String) -> void:
	if cond:
		print("ok " + label)
	else:
		_failures += 1
		print("FAIL " + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame
	var inv: PartyInventory = scene._party_inventory

	# Give the party a Rare Chest piece and some Wild Berries directly (bypassing the demo's own
	# seeded content, which may or may not include these -- this test only needs to prove the
	# professions loop, not re-verify InventoryDemoSetup's seed). InventoryDemoSetup.seed_demo_party()
	# already seeds 4 Bag Gear items (uncommon_cloak/rare_gauntlets/epic_charm/lucky_pebble), so our
	# appended chest lands at whatever index it lands at, NOT index 0 -- the plan's own literal
	# snippet's hardcoded select_breakdown_item_for_test(0) would salvage the wrong (pre-seeded) item
	# instead of the one this test actually cares about; look up the real index instead of assuming it.
	var old_chest: Gear = Gear.new()
	old_chest.display_name = "Old Chestplate"
	old_chest.slot = Gear.Slot.CHEST
	old_chest.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(old_chest)
	var chest_index: int = inv.gear.find(old_chest)
	var berries: CraftingMaterial = CraftingMaterial.new()
	berries.material_type = &"forage_herb"
	berries.rarity = RarityVisuals.Rarity.COMMON
	berries.quantity = 4
	inv.give_material(berries)

	scene._toggle_professions()
	var panel: ProfessionsMenuPanel = scene._professions_panel
	_check(panel.is_open(), "Professions panel opens via the real 'P' hotkey path in town_demo")

	# Salvage the Chest, then craft a new one with Tempering Reels.
	panel.select_breakdown_item_for_test(chest_index)
	panel.press_breakdown_confirm_for_test()
	# The plan's own literal snippet asserted `inv.materials.size() == 1` here -- but this test
	# already gave the party a Wild Berries (forage_herb) material stack BEFORE opening the panel
	# (for the later Cooking step), so materials already held 1 entry before Break Down ever ran;
	# checking for the specific Rare Scrap entry (not the array's total size) is what actually proves
	# Break Down worked, and doesn't depend on what else happens to be in Materials at the time.
	var scrap: CraftingMaterial = null
	for m: CraftingMaterial in inv.materials:
		if m.material_type == SalvageSystem.SCRAP_MATERIAL_TYPE and m.rarity == RarityVisuals.Rarity.RARE:
			scrap = m
	_check(scrap != null, "Break Down grants Rare Scrap through the real scene")

	panel.select_craft_slot_for_test(Gear.Slot.CHEST)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	panel.toggle_tempering_for_test()
	panel.press_craft_confirm_for_test()
	for i in range(panel.tempering_panel_for_test().reel_count_for_test()):
		panel.tempering_panel_for_test().press_stop_for_test(i)
	panel.tempering_panel_for_test().press_confirm_for_test()
	var new_chest: Gear = null
	for g: Gear in inv.gear:
		if g.slot == Gear.Slot.CHEST:
			new_chest = g
	_check(new_chest != null, "a new Chest piece was crafted through the full Salvage -> Tempering Reels -> Craft loop")

	# Cook Wildberry Jam with Second Helping, then use it via the SAME item-staging path Healing
	# Potion already uses (MainPhasePlan.toggle_item / PartyInventory.find_item/consume_item).
	panel.switch_to_cooking_for_test()
	panel.select_cooking_recipe_for_test(&"wildberry_jam")
	panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	panel.toggle_second_helping_for_test()
	panel.press_cook_confirm_for_test()
	panel.second_helping_panel_for_test().press_bank_for_test()
	var jam: ConsumableItem = inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON)
	_check(jam != null, "Wildberry Jam was cooked through the full Cook -> Second Helping loop")

	scene._toggle_professions()

	# The cooked food stages/consumes through combat's Item Reel exactly like Healing Potion --
	# construct a standalone MainPhasePlan against the same inventory (this test doesn't need a
	# running combat.tscn instance to prove the staging contract itself).
	var c: Combatant = Combatant.new()
	c.resource_pool = ResourcePool.new()
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	_check(plan.can_stage_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON), "the cooked Jam is stageable via MainPhasePlan.can_stage_item(), the same entry point Healing Potion uses")
	plan.toggle_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON)
	_check(plan.staged_item_type == &"wildberry_jam" and plan.staged_item_rarity == RarityVisuals.Rarity.COMMON, "staging records both the item_type and rarity")
	var quantity_before: int = jam.quantity
	plan.commit()
	# PartyInventory.consume_item() documents removing the (item_type, rarity) entry entirely once its
	# quantity hits 0 -- Second Helping's bank-with-zero-rerolls path (used above) yields no bonus
	# quantity, so quantity_before is exactly 1 here and the stack is fully consumed, not left at 0;
	# find_item() correctly returns null in that case. The plan's own literal snippet assumed a
	# still-present entry with quantity_before - 1 > 0, which doesn't hold for a 1-unit stack.
	var remaining: ConsumableItem = inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON)
	var remaining_qty: int = remaining.quantity if remaining != null else 0
	_check(remaining_qty == quantity_before - 1, "commit() consumes exactly 1 unit of the staged (type, rarity) stack")
	_check(c.item_use_reel != null and c.pending_item_base_heal == jam.heal_amount, "commit() wires the Item Reel + pending heal exactly like Healing Potion's existing path")

	print(("ok" if _failures == 0 else "FAIL") + " Salvaging + Cooking professions end-to-end smoke test complete")
	quit(_failures)
