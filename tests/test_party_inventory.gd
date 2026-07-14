extends SceneTree

# Headless test: PartyInventory's unified Bag capacity (Gear+Weapons+Items); Materials/Quest stay uncapped.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(inv.bag_capacity() == 20, "0 companion slots -> 20 base capacity (got %d)" % inv.bag_capacity())

	inv.unlocked_companion_slots = 1
	_check(inv.bag_capacity() == 30, "1 companion slot -> 30 capacity (got %d)" % inv.bag_capacity())

	inv.unlocked_companion_slots = 2
	_check(inv.bag_capacity() == 40, "2 companion slots -> 40 capacity (got %d)" % inv.bag_capacity())

	# bag_count() sums gear + weapons + items (each stack counts once), NOT materials/quest_items.
	_check(inv.bag_count() == 0, "a fresh inventory has bag_count() 0")
	for i: int in range(37):
		inv.gear.append(Gear.new())
	inv.weapons.append(Weapon.new())
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.quantity = 5
	inv.items.append(potion)
	_check(inv.bag_count() == 39, "gear(37) + weapons(1) + items(1 stack, qty 5) = 39 slots (got %d)" % inv.bag_count())
	_check(inv.can_add_to_bag(), "39 < 40 capacity -> room for one more")

	inv.gear.append(Gear.new())
	_check(inv.bag_count() == 40, "one more gear entry -> 40 (got %d)" % inv.bag_count())
	_check(not inv.can_add_to_bag(), "at capacity (40 >= 40) -> no room")

	# A separate inventory (not `inv`, which the pre-existing "Materials tab uncapped" check below
	# still needs empty) proves materials never count toward bag_count().
	var mat_check_inv: PartyInventory = PartyInventory.new()
	for i: int in range(38):
		mat_check_inv.gear.append(Gear.new())
	for i: int in range(500):
		mat_check_inv.materials.append(Resource.new())
	_check(mat_check_inv.bag_count() == 38, "materials never count toward bag_count() (got %d)" % mat_check_inv.bag_count())

	# try_give_gear()/try_give_weapon(): fail at capacity, leave the bag unchanged.
	var full_inv: PartyInventory = PartyInventory.new()
	for i: int in range(20):
		full_inv.gear.append(Gear.new())
	var new_gear: Gear = Gear.new()
	_check(not full_inv.try_give_gear(new_gear), "try_give_gear() fails when the bag is full")
	_check(not full_inv.gear.has(new_gear), "a failed try_give_gear() leaves the bag untouched")
	_check(full_inv.gear.size() == 20, "bag size is unchanged after the failed grant (got %d)" % full_inv.gear.size())

	full_inv.gear.pop_back()
	_check(full_inv.try_give_gear(new_gear), "try_give_gear() succeeds once there's room")
	_check(full_inv.gear.has(new_gear), "the granted item is now in the bag")

	var full_inv2: PartyInventory = PartyInventory.new()
	for i: int in range(20):
		full_inv2.weapons.append(Weapon.new())
	var new_weapon: Weapon = Weapon.new()
	_check(not full_inv2.try_give_weapon(new_weapon), "try_give_weapon() fails when the bag is full")
	full_inv2.weapons.pop_back()
	_check(full_inv2.try_give_weapon(new_weapon), "try_give_weapon() succeeds once there's room")

	# try_give_item(): merging into an EXISTING stack always succeeds, even at capacity, because it
	# never grows bag_count(). A genuinely NEW stack entry is capacity-gated like gear/weapons.
	var full_inv3: PartyInventory = PartyInventory.new()
	var existing_potion: ConsumableItem = ConsumableItem.new()
	existing_potion.item_type = &"healing_potion"
	existing_potion.quantity = 1
	full_inv3.items.append(existing_potion)
	for i: int in range(19):
		full_inv3.gear.append(Gear.new())
	_check(not full_inv3.can_add_to_bag(), "sanity check: this inventory is at capacity (20/20)")

	var more_potions: ConsumableItem = ConsumableItem.new()
	more_potions.item_type = &"healing_potion"
	more_potions.quantity = 3
	_check(full_inv3.try_give_item(more_potions), "merging into an existing stack succeeds even at capacity")
	_check(existing_potion.quantity == 4, "the existing stack's quantity grew by the merged amount (got %d)" % existing_potion.quantity)

	var mana_potion: ConsumableItem = ConsumableItem.new()
	mana_potion.item_type = &"mana_potion"
	mana_potion.quantity = 1
	_check(not full_inv3.try_give_item(mana_potion), "a genuinely NEW stack entry is capacity-gated, so this fails at capacity")
	_check(full_inv3.find_item(&"mana_potion") == null, "the rejected new item type was not added")

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
