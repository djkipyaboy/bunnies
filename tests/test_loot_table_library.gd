extends SceneTree

# Headless test: LootTableLibrary — the shared overworld_trash loot table (2026-07-12 combat loot
# drops spec). Mirrors tests/test_encounter_library.gd's own smoke-test shape.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_loot_table_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(LootTableLibrary.IDS.has(&"overworld_trash"), "IDS includes overworld_trash")

	var table: LootTable = LootTableLibrary.make(&"overworld_trash")
	_check(table != null, "make(&overworld_trash) returns a LootTable")
	_check(table.entries.size() == 3, "overworld_trash has 3 entries (got %d)" % table.entries.size())

	for entry: LootEntry in table.entries:
		_check(entry.item is Gear, "every entry's item is a Gear")
		var g: Gear = entry.item as Gear
		_check(not g.display_name.is_empty(), "entry item has a non-empty display_name")
		_check(g.rarity == RarityVisuals.Rarity.COMMON or g.rarity == RarityVisuals.Rarity.UNCOMMON,
			"entry item is Common or Uncommon (got %s)" % RarityVisuals.display_name(g.rarity))
		_check(entry.drop_chance > 0.0 and entry.drop_chance <= 1.0, "entry has a valid drop_chance (got %f)" % entry.drop_chance)

	var table2: LootTable = LootTableLibrary.make(&"overworld_trash")
	_check(table2 != table, "make() returns a FRESH LootTable instance each call")
	_check(table2.entries[0].item != table.entries[0].item, "fresh instances don't share item Resources either")

	_check(LootTableLibrary.make(&"not_a_real_id") == null, "an unknown id returns null")

	print(("LOOT TABLE LIBRARY TEST PASSED" if _failures == 0 else "LOOT TABLE LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
