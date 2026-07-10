extends SceneTree

# Headless test: LootTable rolls are INDEPENDENT per entry (WoW-style), not a single weighted pick.
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

func _initialize() -> void:
	var item_a: Resource = Resource.new()
	var item_b: Resource = Resource.new()

	# Two 100% entries: both always drop together (proves independence, not a single pick).
	var certain: LootTable = LootTable.new()
	certain.entries = [_entry(item_a, 1.0), _entry(item_b, 1.0)]
	var drops: Array = LootTable.roll(certain)
	_check(drops.size() == 2 and item_a in drops and item_b in drops, "two 100%% entries both always drop (got %d)" % drops.size())

	# One 0%, one 100%: exactly the 100% one drops, every time.
	var mixed: LootTable = LootTable.new()
	mixed.entries = [_entry(item_a, 0.0), _entry(item_b, 1.0)]
	for i: int in range(20):
		var d: Array = LootTable.roll(mixed)
		_check(d.size() == 1 and d[0] == item_b, "0%% never drops, 100%% always does (trial %d)" % i)

	# Empty table -> empty drops, no crash.
	var empty: LootTable = LootTable.new()
	_check(LootTable.roll(empty).size() == 0, "empty table -> no drops")

	print(("LOOT TABLE TEST PASSED" if _failures == 0 else "LOOT TABLE TEST FAILED: %d" % _failures))
	quit(_failures)
