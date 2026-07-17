extends SceneTree

# Headless end-to-end test: the full general-store path (2026-07-17 design §5's last bullet) through
# a REAL town_demo.tscn instance — interact with the Shopkeeper, choose Shop, buy a piece of Gear and
# a Healing Potion, confirm Amber/Bag/stock all update; separately confirm Talk still plays dialogue
# and Leave does nothing. Uses the SceneTree._process()-driven multi-frame pattern
# tests/test_shared_party_state.gd already established for this exact scene.

var _town_instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		var town: TownDemo = _town_instance
		var starting_amber: int = town._party_inventory.amber
		_check(starting_amber == 30, "the town's fresh-seeded party starts with 30 Amber (got %d)" % starting_amber)

		# Find the Shopkeeper node the way a real player's interact would resolve it.
		var shopkeeper: Villager = town._interior.get_node("Shopkeeper")
		_check(shopkeeper.is_vendor, "the Shopkeeper is wired as a vendor")

		# Drive the exact interact chain: Villager.interact() -> _on_vendor_interacted -> VendorPromptPanel.
		shopkeeper._on_interacted()
		_check(town._vendor_prompt_panel.is_open(), "interacting with the Shopkeeper opens the vendor prompt")

		# Leave does nothing but close the prompt.
		town._vendor_prompt_panel.press_leave_for_test()
		_check(not town._vendor_prompt_panel.is_open(), "Leave closes the prompt")
		_check(town._party_inventory.amber == starting_amber, "Leave doesn't touch Amber")

		# Talk falls through to the existing linear DialogueBox. The Shopkeeper's dialogue
		# (town_demo.gd's _make_dialogue()) is actually a 2-line set (greeting + "Safe travels!"
		# farewell), not the 1-line set the original brief assumed — advance() twice to close it,
		# matching DialogueBox's real semantics (tests/test_dialogue_box.gd's 2-line case).
		shopkeeper._on_interacted()
		town._vendor_prompt_panel.press_talk_for_test()
		_check(town._dialogue_box.is_open(), "Talk opens the existing DialogueBox")
		town._dialogue_box.advance()
		_check(town._dialogue_box.is_open(), "advancing to the farewell line keeps the box open")
		town._dialogue_box.advance()
		_check(not town._dialogue_box.is_open(), "the dialogue closes after its farewell line")

		# Shop opens ShopPanel with the town's real, persisted stock.
		shopkeeper._on_interacted()
		town._vendor_prompt_panel.press_shop_for_test()
		_check(town._shop_panel.is_open(), "Shop opens the ShopPanel")

		var gear_entry: ShopStockEntry = null
		var potion_entry: ShopStockEntry = null
		for e: ShopStockEntry in town._shop_stock:
			if e.item is Gear and gear_entry == null:
				gear_entry = e
			elif e.item is ConsumableItem:
				potion_entry = e
		_check(gear_entry != null, "the town's real catalog includes at least one Gear entry")
		_check(potion_entry != null, "the town's real catalog includes the Healing Potion entry")

		# The demo's real seeded Bag (InventoryDemoSetup.seed_demo_party()) already carries 4
		# non-stacking Gear items and 1 Healing Potion stack — capture the real starting counts
		# rather than assuming an empty Bag (the original brief's `== 1` assumed a fresh-empty Bag).
		var starting_gear_count: int = town._party_inventory.gear.size()
		var starting_items_count: int = town._party_inventory.items.size()

		town._shop_panel.buy_for_test(gear_entry)
		_check(town._party_inventory.amber == starting_amber - 1, "buying the Gear entry spends 1 Amber")
		_check(gear_entry.stock == 2, "buying the Gear entry decrements its stock (3 -> 2)")
		_check(town._party_inventory.gear.size() == starting_gear_count + 1, "the bought Gear item landed in the real Bag")

		town._shop_panel.buy_for_test(potion_entry)
		_check(town._party_inventory.amber == starting_amber - 2, "buying the potion spends another 1 Amber")
		# The demo already seeds a "healing_potion" stack, so the purchase MERGES into it
		# (PartyInventory.try_give_item()'s stacking rule) rather than adding a new stack entry —
		# the stack COUNT stays the same, but its quantity grows.
		var potion_stack: ConsumableItem = town._party_inventory.find_item(&"healing_potion")
		_check(town._party_inventory.items.size() == starting_items_count, "the bought potion merges into the existing stack, not a new one")
		_check(potion_stack != null and potion_stack.quantity == 4, "the bought potion's quantity landed in the real Bag's stack (3 -> 4)")

		town._shop_panel.close()

	if _frames >= 3:
		_town_instance.free()
		print("ok shop end-to-end regression complete")
		return true
	return false
