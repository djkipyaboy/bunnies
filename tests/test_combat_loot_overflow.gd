extends SceneTree

# Headless test: combat-loot overflow when the Bag is already full at bag_capacity(). Mirrors
# tests/test_combat_loot.gd's shape (2026-07-14-ground-item-pickups-design.md §3.3).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loot_overflow.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_stub_table(item_name: String) -> LootTable:
	var item: Gear = Gear.new()
	item.display_name = item_name
	var entry: LootEntry = LootEntry.new()
	entry.item = item
	entry.drop_chance = 1.0
	var t: LootTable = LootTable.new()
	t.entries = [entry]
	return t

func _initialize() -> void:
	var handoff: Node = get_root().get_node("CombatHandoff")
	handoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	for i: int in range(inv.bag_capacity()):   # fill the bag to capacity BEFORE the fight
		inv.gear.append(Gear.new())
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	handoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"OverflowTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._fight_overflow_items.is_empty(), "no overflow yet before any kill")

	var stub_table: LootTable = _make_stub_table("Overflow Drop")
	inst._enemies[0].loot_table = stub_table
	inst._enemies[0].take_damage(9999)

	_check(inv.gear.size() == inv.bag_capacity(), "the full bag did not grow (drop was not granted)")
	_check(inst._fight_overflow_items.size() == 1, "the drop lands in _fight_overflow_items instead (got %d)" % inst._fight_overflow_items.size())
	_check(inst._fight_overflow_items[0].display_name == "Overflow Drop", "the overflow item carries the dropped item's display_name")
	_check(inst._fight_loot_names.is_empty(), "the overflow drop is NOT counted as granted loot")

	inst._turn_manager.advance_turn()   # the only real enemy is dead -> win
	var result_label: Label = inst._overlay.get_node("ResultLabel")
	_check(result_label.text.find("Bag was full") != -1, "the result card mentions the left-behind item (got '%s')" % result_label.text)
	_check(result_label.text.find("Overflow Drop") != -1, "the result card names the left-behind item")

	# Continue: the overflow item(s) copy into CombatHandoff.pending_ground_drops.
	var return_path: String = inst.press_continue_for_test()
	_check(return_path == "res://world/overworld_demo.tscn", "press_continue_for_test() returns the return scene path")
	_check(handoff.pending_ground_drops.size() == 1, "pending_ground_drops carries the overflow item (got %d)" % handoff.pending_ground_drops.size())
	_check((handoff.pending_ground_drops[0] as Gear).display_name == "Overflow Drop", "the carried item is the same overflow drop")

	inst.queue_free()
	await process_frame
	handoff.clear_pending()

	print(("COMBAT LOOT OVERFLOW TEST PASSED" if _failures == 0 else "COMBAT LOOT OVERFLOW TEST FAILED: %d" % _failures))
	quit(_failures)
