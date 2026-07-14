extends SceneTree

# Headless test: PartyInventory's Gear-tab cap (20 + 10/unlocked companion slot); other tabs uncapped.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(inv.gear_capacity() == 20, "0 companion slots -> 20 base capacity (got %d)" % inv.gear_capacity())

	inv.unlocked_companion_slots = 1
	_check(inv.gear_capacity() == 30, "1 companion slot -> 30 capacity (got %d)" % inv.gear_capacity())

	inv.unlocked_companion_slots = 2
	_check(inv.gear_capacity() == 40, "2 companion slots -> 40 capacity (got %d)" % inv.gear_capacity())

	# Capacity is slot-unlock-driven, not active-headcount-driven — filling the array to capacity
	# blocks further adds regardless of how many companions are CURRENTLY active.
	for i: int in range(40):
		inv.gear.append(Gear.new())
	_check(not inv.can_add_gear(), "Gear tab full at capacity refuses further adds")
	inv.gear.pop_back()
	_check(inv.can_add_gear(), "Gear tab under capacity allows adds")

	# Other tabs are uncapped.
	for i: int in range(500):
		inv.materials.append(Resource.new())
	_check(inv.materials.size() == 500, "Materials tab uncapped (got %d)" % inv.materials.size())

	# give_material() stacks by material_type (design-bible 27-crafting.md §11) rather than growing
	# the array unbounded — a fresh inventory so the 500 plain Resources above don't interfere.
	var stack_inv: PartyInventory = PartyInventory.new()
	var berries1: CraftingMaterial = CraftingMaterial.new()
	berries1.material_type = &"forage_herb"
	berries1.display_name = "Wild Berries"
	berries1.quantity = 1
	stack_inv.give_material(berries1)
	_check(stack_inv.materials.size() == 1, "give_material() adds a new entry for a new material_type")
	_check(stack_inv.materials[0].quantity == 1, "the new entry starts at its own quantity")

	var berries2: CraftingMaterial = CraftingMaterial.new()
	berries2.material_type = &"forage_herb"
	berries2.quantity = 2
	stack_inv.give_material(berries2)
	_check(stack_inv.materials.size() == 1, "give_material() stacks onto the existing entry instead of adding a second one")
	_check(stack_inv.materials[0].quantity == 3, "stacking sums the quantities (1 + 2 = 3)")

	var fish: CraftingMaterial = CraftingMaterial.new()
	fish.material_type = &"fish_meat"
	fish.quantity = 1
	stack_inv.give_material(fish)
	_check(stack_inv.materials.size() == 2, "a different material_type adds a second, separate entry")

	# --- items (2026-07-14 combat items menu): give_item()/find_item()/consume_item() ---
	var potion_inv: PartyInventory = PartyInventory.new()
	var potion1: ConsumableItem = ConsumableItem.new()
	potion1.item_type = &"healing_potion"
	potion1.display_name = "Healing Potion"
	potion1.heal_amount = 30
	potion1.quantity = 1
	potion_inv.give_item(potion1)
	_check(potion_inv.items.size() == 1, "give_item() adds a new entry for a new item_type")
	_check(potion_inv.items[0].quantity == 1, "the new entry starts at its own quantity")

	var potion2: ConsumableItem = ConsumableItem.new()
	potion2.item_type = &"healing_potion"
	potion2.quantity = 2
	potion_inv.give_item(potion2)
	_check(potion_inv.items.size() == 1, "give_item() stacks onto the existing entry instead of adding a second one")
	_check(potion_inv.items[0].quantity == 3, "stacking sums the quantities (1 + 2 = 3)")

	_check(potion_inv.find_item(&"healing_potion") == potion_inv.items[0], "find_item() returns the matching entry")
	_check(potion_inv.find_item(&"mana_potion") == null, "find_item() returns null for an unowned item_type")

	potion_inv.consume_item(&"healing_potion")
	_check(potion_inv.items[0].quantity == 2, "consume_item() decrements quantity by 1 (got %d)" % potion_inv.items[0].quantity)
	potion_inv.consume_item(&"healing_potion")
	potion_inv.consume_item(&"healing_potion")
	_check(potion_inv.items.is_empty(), "consume_item() removes the entry once quantity hits 0")
	potion_inv.consume_item(&"healing_potion")
	_check(potion_inv.items.is_empty(), "consume_item() no-ops safely when the item_type isn't owned")

	print(("PARTY INVENTORY TEST PASSED" if _failures == 0 else "PARTY INVENTORY TEST FAILED: %d" % _failures))
	quit(_failures)
