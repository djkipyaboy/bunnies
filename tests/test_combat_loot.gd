extends SceneTree

# Headless test: the 2026-07-12 combat loot-drops loop (combat.gd's _on_enemy_defeated granting
# LootTable rolls into _party_inventory). Mirrors tests/test_combat_xp.gd's shape exactly. Uses a
# guaranteed-drop stub LootTable (not the real overworld_trash table's probabilistic chances) so
# the loot-granting assertions are deterministic — EnemyLibrary's own wiring is already covered by
# tests/test_enemy_library.gd.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loot.gd

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
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# --- Handoff-path kill grants a DUPLICATED item into the real PartyInventory ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"LootTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._party_inventory == inv, "_build_combatants() captures the handoff's PartyInventory")
	_check(inst._fight_loot_names.is_empty(), "no loot yet before any kill")

	var stub_table: LootTable = _make_stub_table("Test Drop")
	inst._enemies[0].loot_table = stub_table   # override for a deterministic (guaranteed) drop

	inst._enemies[0].take_damage(9999)
	_check(not inst._enemies[0].is_alive(), "the enemy is actually dead")
	_check(inv.gear.size() == 1, "the dropped item lands in the real PartyInventory (got %d items)" % inv.gear.size())
	_check(inv.gear[0].display_name == "Test Drop", "the granted item carries the dropped item's display_name")
	_check(inv.gear[0] != stub_table.entries[0].item, "the granted item is a DUPLICATE, not the table's own template reference")
	_check(inst._fight_loot_names == ["Test Drop"], "_fight_loot_names accumulates the dropped item's name")

	inst._turn_manager.advance_turn()   # the only real enemy is dead -> this ends combat as a win
	_check(inst._overlay.visible, "the result card shows once combat ends")
	var result_label: Label = inst._overlay.get_node("ResultLabel")
	_check(result_label.text.find("Loot: Test Drop") != -1, "the result card shows the loot line (got '%s')" % result_label.text)

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory exists, loot must not be granted or crash ---
	CombatHandoff.clear_pending()
	Combat._pc_class_ids = [&"warrior"]
	Combat._enemy_ids = [&"rat"]
	Combat._dummies_enabled = false
	Combat._endgame_enabled = false

	var standalone_scene: PackedScene = load("res://combat/combat.tscn")
	var standalone: Combat = standalone_scene.instantiate()
	get_root().add_child(standalone)
	await process_frame
	await process_frame

	# Standalone launches don't auto-start combat (test_combat_handoff_entry.gd already asserts
	# round_number == 0 right after instantiation) — _build_combatants() only runs once BEGIN FIGHT
	# is pressed. Drive that directly, same as tests/test_scene_party_smoke.gd, so _enemies is
	# actually populated before this test touches it.
	standalone._start_combat()
	await process_frame

	_check(standalone._party_inventory == null, "standalone launches never capture a PartyInventory")
	standalone._enemies[0].loot_table = _make_stub_table("Should Never Grant")
	standalone._enemies[0].take_damage(9999)
	_check(not standalone._enemies[0].is_alive(), "the standalone enemy is also actually dead")
	_check(standalone._fight_loot_names.is_empty(), "standalone mode never accumulates loot names (nothing to grant it into)")

	standalone._turn_manager.advance_turn()
	var standalone_result_label: Label = standalone._overlay.get_node("ResultLabel")
	_check(standalone_result_label.text.find("Loot:") == -1, "standalone mode's result card never shows a loot line")

	standalone.queue_free()
	await process_frame

	print(("COMBAT LOOT TEST PASSED" if _failures == 0 else "COMBAT LOOT TEST FAILED: %d" % _failures))
	quit(_failures)
