extends SceneTree

# Headless test: LootTable rolls are INDEPENDENT per entry (WoW-style), not a single weighted pick,
# and every drop is a DUPLICATE of its LootEntry.item template, never the same object (2026-07-12
# fix — two drops of the same entry, or the same table rolled across multiple kills, must not hand
# out aliased Resources).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_loot_table.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _entry(item: Resource, chance: float) -> LootEntry:
	var e: LootEntry = LootEntry.new()
	e.item = item
	e.drop_chance = chance
	return e

func _make_item(item_name: String) -> Gear:
	var g: Gear = Gear.new()
	g.display_name = item_name
	return g

func _initialize() -> void:
	var item_a: Gear = _make_item("Item A")
	var item_b: Gear = _make_item("Item B")

	# Two 100% entries: both always drop together (proves independence, not a single pick).
	var certain: LootTable = LootTable.new()
	certain.entries = [_entry(item_a, 1.0), _entry(item_b, 1.0)]
	var drops: Array = LootTable.roll(certain)
	_check(drops.size() == 2, "two 100%% entries both always drop (got %d)" % drops.size())
	var names: Array[String] = []
	for d: Resource in drops:
		names.append((d as Gear).display_name)
	_check(names.has("Item A") and names.has("Item B"), "both entries' items are represented by display_name")
	_check(not drops.has(item_a) and not drops.has(item_b), "roll() returns DUPLICATES, not the same template references")

	# One 0%, one 100%: exactly the 100% one drops, every time, as a duplicate.
	var mixed: LootTable = LootTable.new()
	mixed.entries = [_entry(item_a, 0.0), _entry(item_b, 1.0)]
	for i: int in range(20):
		var d: Array = LootTable.roll(mixed)
		var ok: bool = d.size() == 1 and (d[0] as Gear).display_name == "Item B" and d[0] != item_b
		_check(ok, "0%% never drops, 100%% always does as a duplicate (trial %d)" % i)

	# Empty table -> empty drops, no crash.
	var empty: LootTable = LootTable.new()
	_check(LootTable.roll(empty).size() == 0, "empty table -> no drops")

	# An entry with its item left unset (null) at 100% is silently skipped — no crash, no drop —
	# while a sibling 100% entry with a real item in the same table still drops normally.
	var unset: LootTable = LootTable.new()
	unset.entries = [_entry(null, 1.0), _entry(item_a, 1.0)]
	var unset_drops: Array = LootTable.roll(unset)
	_check(unset_drops.size() == 1 and (unset_drops[0] as Gear).display_name == "Item A",
			"null-item 100%% entry is skipped, sibling real 100%% entry still drops (got %d)" % unset_drops.size())

	print(("LOOT TABLE TEST PASSED" if _failures == 0 else "LOOT TABLE TEST FAILED: %d" % _failures))
	quit(_failures)
