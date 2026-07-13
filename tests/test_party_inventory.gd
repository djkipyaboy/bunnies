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

	print(("PARTY INVENTORY TEST PASSED" if _failures == 0 else "PARTY INVENTORY TEST FAILED: %d" % _failures))
	quit(_failures)
