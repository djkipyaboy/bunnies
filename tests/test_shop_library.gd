extends SceneTree

# Headless test: ShopLibrary.general_store() (2026-07-17 general store design §3.3/§3.4, weapon
# variety extended 2026-07-18) — the authored 45-entry catalog. Mirrors tests/test_loot_table_library.gd's shape.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var stock: Array[ShopStockEntry] = ShopLibrary.general_store()
	_check(stock.size() == 45, "general_store() returns exactly 45 entries (got %d)" % stock.size())

	var gear_count: int = 0
	var weapon_count: int = 0
	var potion_count: int = 0
	for entry: ShopStockEntry in stock:
		if entry.item is Gear:
			gear_count += 1
			var g: Gear = entry.item as Gear
			_check(entry.price == 1, "%s costs 1 Amber (got %d)" % [g.display_name, entry.price])
			_check(entry.stock == 3, "%s stocks 3 units (got %d)" % [g.display_name, entry.stock])
			var s: Stats = g.stat_bonuses
			var nonzero: int = 0
			for v in [s.might, s.finesse, s.vigor, s.focus, s.grit, s.luck]:
				if v != 0:
					nonzero += 1
			_check(nonzero <= RarityVisuals.max_stat_affixes(g.rarity), "%s (%s) respects its rarity's max_stat_affixes (got %d nonzero stats)" % [g.display_name, RarityVisuals.display_name(g.rarity), nonzero])
			_check(g.reel_affixes.is_empty(), "%s carries no reel_affixes (ReelAffix has no resolver wiring yet)" % g.display_name)
		elif entry.item is Weapon:
			weapon_count += 1
			var w: Weapon = entry.item as Weapon
			_check(entry.price == 1, "%s costs 1 Amber (got %d)" % [w.display_name, entry.price])
			_check(entry.stock == 3, "%s stocks 3 units (got %d)" % [w.display_name, entry.stock])
			_check(w.rarity == RarityVisuals.Rarity.COMMON or w.rarity == RarityVisuals.Rarity.UNCOMMON, "%s is Common or Uncommon only (got %s)" % [w.display_name, RarityVisuals.display_name(w.rarity)])
			_check(not w.reels.is_empty(), "%s has real action reels" % w.display_name)
		elif entry.item is ConsumableItem:
			potion_count += 1
			var p: ConsumableItem = entry.item as ConsumableItem
			_check(entry.price == 1, "%s costs 1 Amber (got %d)" % [p.display_name, entry.price])
			_check(entry.stock == 99, "%s stocks 99 units (got %d)" % [p.display_name, entry.stock])

	_check(gear_count == 30, "30 Gear entries: 4 slots x 5 rarities + Charm x2 variants x 5 rarities (got %d)" % gear_count)
	_check(weapon_count == 14, "14 Weapon entries: one Common + one Uncommon per class, 7 classes (got %d)" % weapon_count)
	_check(potion_count == 1, "1 Healing Potion catalog line (got %d)" % potion_count)

	# Two independent calls must never alias the same Resource instances (mirrors LootTable.roll()'s
	# duplicate-on-grant precedent) — otherwise two ShopPanel opens across a scene reload would share
	# mutable state that was never meant to be shared.
	var stock2: Array[ShopStockEntry] = ShopLibrary.general_store()
	_check(stock[0] != stock2[0], "two calls to general_store() return DIFFERENT ShopStockEntry instances")
	_check(stock[0].item != stock2[0].item, "two calls to general_store() return DIFFERENT underlying item instances")

	print(("SHOP LIBRARY TEST PASSED" if _failures == 0 else "SHOP LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
