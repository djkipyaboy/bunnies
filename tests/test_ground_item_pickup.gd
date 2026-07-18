extends SceneTree

# Headless test: GroundItemPickup grants its held item on interact(), stays put and signals
# rejection when the Bag is full, and its floating label toggles with set_highlighted()
# (2026-07-14-ground-item-pickups-design.md §3.2).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ground_item_pickup.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- Gear: successful pickup frees the node and grants into the bag ---
	var inv: PartyInventory = PartyInventory.new()
	var sword: Gear = Gear.new()
	sword.display_name = "Test Sword"
	sword.rarity = RarityVisuals.Rarity.UNCOMMON

	var pickup: GroundItemPickup = GroundItemPickup.new()
	pickup.item = sword
	pickup.party_inventory = inv
	get_root().add_child(pickup)
	await process_frame

	# GDScript lambdas capture outer locals BY VALUE — reassigning a plain captured String inside
	# the lambda would not propagate back out, so use a 1-element Array (a reference type) instead.
	var picked_up_name: Array = [""]
	pickup.item_picked_up.connect(func(n: String): picked_up_name[0] = n)
	pickup.interact()
	_check(inv.gear.has(sword), "interact() grants the Gear item into the PartyInventory")
	_check(picked_up_name[0] == "Test Sword", "item_picked_up carries the display name")
	await process_frame
	_check(not is_instance_valid(pickup), "a successful pickup frees itself")

	# --- ConsumableItem: successful pickup ---
	var inv2: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Test Potion"
	potion.quantity = 3
	var pickup2: GroundItemPickup = GroundItemPickup.new()
	pickup2.item = potion
	pickup2.party_inventory = inv2
	get_root().add_child(pickup2)
	await process_frame
	pickup2.interact()
	_check(inv2.find_item(&"healing_potion") != null and inv2.find_item(&"healing_potion").quantity == 3,
		"interact() grants a ConsumableItem via try_give_item()")

	# --- CraftingMaterial: always succeeds (uncapped) ---
	var inv3: PartyInventory = PartyInventory.new()
	var ore: CraftingMaterial = CraftingMaterial.new()
	ore.material_type = &"iron_ore"
	ore.display_name = "Test Ore"
	ore.quantity = 2
	var pickup3: GroundItemPickup = GroundItemPickup.new()
	pickup3.item = ore
	pickup3.party_inventory = inv3
	get_root().add_child(pickup3)
	await process_frame
	pickup3.interact()
	_check(inv3.materials.size() == 1 and inv3.materials[0].quantity == 2, "interact() grants a CraftingMaterial via give_material()")

	# --- QuestItem: always succeeds (uncapped, 2026-07-18 lock-and-key design) ---
	var inv4: PartyInventory = PartyInventory.new()
	var key: QuestItem = QuestItem.new()
	key.item_id = &"dungeon_key"
	key.display_name = "Rusty Key"
	var pickup_key: GroundItemPickup = GroundItemPickup.new()
	pickup_key.item = key
	pickup_key.party_inventory = inv4
	get_root().add_child(pickup_key)
	await process_frame
	pickup_key.interact()
	_check(inv4.has_quest_item(&"dungeon_key"), "interact() grants a QuestItem via give_quest_item()")

	# --- Bag full: rejection leaves the item on the ground, does NOT free the node ---
	var full_inv: PartyInventory = PartyInventory.new()
	for i: int in range(20):
		full_inv.gear.append(Gear.new())
	var shield: Gear = Gear.new()
	shield.display_name = "Rejected Shield"
	var pickup4: GroundItemPickup = GroundItemPickup.new()
	pickup4.item = shield
	pickup4.party_inventory = full_inv
	get_root().add_child(pickup4)
	await process_frame

	var rejected_name: Array = [""]
	pickup4.pickup_rejected.connect(func(n: String): rejected_name[0] = n)
	pickup4.interact()
	_check(not full_inv.gear.has(shield), "a rejected pickup does not grant the item")
	_check(rejected_name[0] == "Rejected Shield", "pickup_rejected fires with the item's name")
	await process_frame
	_check(is_instance_valid(pickup4), "a rejected pickup does NOT free itself — it stays on the ground")

	# --- Floating label toggles with set_highlighted(), not alpha-dimmed ---
	pickup4.set_highlighted(true)
	_check(pickup4._proximity_label.visible, "set_highlighted(true) shows the floating label")
	pickup4.set_highlighted(false)
	_check(not pickup4._proximity_label.visible, "set_highlighted(false) hides the floating label")

	# pickup/pickup2/pickup3 already freed themselves via queue_free() inside interact() (their
	# grants succeeded) — only the rejected pickup4 is still alive and needs freeing here.
	pickup4.free()

	print(("GROUND ITEM PICKUP TEST PASSED" if _failures == 0 else "GROUND ITEM PICKUP TEST FAILED: %d" % _failures))
	quit(_failures)
