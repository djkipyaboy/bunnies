extends SceneTree

# View-layer smoke: ShopPanel (2026-07-17 general store design §3.5) — tabbed by slot, buying
# decrements stock/Amber and grants a DUPLICATE into the Bag, a full Bag rejects a Gear/Weapon
# purchase, a Consumable purchase that MERGES into an already-existing stack still succeeds via
# stack-merge regardless of Bag fullness (a brand-new stack's first unit is NOT exempt).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	inv.amber = 5
	var stock: Array[ShopStockEntry] = [
		_gear_line("Test Cap", Gear.Slot.HEADWEAR, 1, 3),
		_potion_line(1, 99),
	]

	var panel: ShopPanel = ShopPanel.new()
	panel.open_for(inv, stock)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visibility")

	# Buying the gear line: Amber decrements, stock decrements, a DUPLICATE lands in the Bag.
	panel.buy_for_test(stock[0])
	_check(inv.amber == 4, "buying the 1-Amber gear line spends 1 Amber (5 -> 4, got %d)" % inv.amber)
	_check(stock[0].stock == 2, "buying decrements the entry's stock (3 -> 2, got %d)" % stock[0].stock)
	_check(inv.gear.size() == 1, "the Bag received exactly one Gear item")
	_check(inv.gear[0] != stock[0].item, "the granted item is a DUPLICATE, not the catalog's own template reference")
	_check(inv.gear[0].display_name == "Test Cap", "the granted duplicate carries the template's display_name")

	# Buying past zero stock is a no-op.
	stock[0].stock = 0
	panel.buy_for_test(stock[0])
	_check(inv.amber == 4, "buying with zero stock is a no-op (Amber unchanged)")
	_check(inv.gear.size() == 1, "buying with zero stock grants nothing (Bag unchanged)")

	# Buying with insufficient Amber is a no-op.
	var pricey: ShopStockEntry = _gear_line("Pricey Hat", Gear.Slot.HEADWEAR, 1, 3)
	inv.amber = 0
	panel.buy_for_test(pricey)
	_check(inv.amber == 0, "buying with 0 Amber against a 1-Amber line is a no-op")
	_check(inv.gear.size() == 1, "insufficient-Amber buying grants nothing")

	# A full Bag rejects a NEW Gear purchase (Amber/stock unchanged). A Consumable purchase that MERGES
	# into an ALREADY-EXISTING stack still succeeds via stack-merge — try_give_item() only bypasses the
	# Bag cap for a merge into an existing entry; the very FIRST unit of a brand-new stack is capacity-
	# gated exactly like Gear/Weapon (verified against the real party_inventory.gd doc comment: "only a
	# genuinely new stack entry is capacity-gated"). So this fixture pre-seeds ONE existing potion
	# before filling the rest of the Bag to capacity, to test a genuine merge, not a fresh stack.
	var full_inv: PartyInventory = PartyInventory.new()
	full_inv.amber = 10
	var existing_potion: ConsumableItem = ConsumableItem.new()
	existing_potion.item_type = &"healing_potion"
	existing_potion.display_name = "Healing Potion"
	existing_potion.heal_amount = 30
	existing_potion.quantity = 1
	full_inv.items = [existing_potion]
	for i in range(full_inv.bag_capacity() - 1):   # -1: the pre-existing potion stack already occupies one slot
		var filler: Gear = Gear.new()
		filler.display_name = "Filler %d" % i
		full_inv.gear.append(filler)
	var full_stock: Array[ShopStockEntry] = [
		_gear_line("Overflow Cap", Gear.Slot.HEADWEAR, 1, 3),
		_potion_line(1, 99),
	]
	panel.open_for(full_inv, full_stock)
	panel.buy_for_test(full_stock[0])
	_check(full_inv.amber == 10, "a full Bag rejects the NEW Gear purchase — Amber unchanged")
	_check(full_stock[0].stock == 3, "a full Bag rejects the NEW Gear purchase — stock unchanged")
	_check(panel._reject_label != null, "a rejected purchase sets the reject label")
	_check(panel.is_ancestor_of(panel._reject_label), "the reject label is actually parented into the panel (previously invisible)")
	panel.buy_for_test(full_stock[1])
	_check(full_inv.amber == 9, "a full Bag still allows a Consumable purchase that MERGES into an existing stack — Amber spent")
	_check(full_inv.items[0].quantity == 2, "the potion purchase merged into the pre-existing stack (1 -> 2), not a new slot")
	panel.buy_for_test(full_stock[1])
	_check(full_inv.items[0].quantity == 3, "a further potion purchase also merges into the same stack")

	panel.free()
	quit()

func _gear_line(name: String, slot: int, price: int, stock: int) -> ShopStockEntry:
	var g: Gear = Gear.new()
	g.display_name = name
	g.slot = slot
	g.stat_bonuses = Stats.new()
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = g
	e.price = price
	e.stock = stock
	return e

func _potion_line(price: int, stock: int) -> ShopStockEntry:
	var p: ConsumableItem = ConsumableItem.new()
	p.item_type = &"healing_potion"
	p.display_name = "Healing Potion"
	p.heal_amount = 30
	p.quantity = 1
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = p
	e.price = price
	e.stock = stock
	return e
