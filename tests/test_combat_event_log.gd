extends SceneTree

# Headless test: the 2026-07-13 cross-scene event log's combat.gd integration — the Won/Lost/XP/
# Loot lines logged in _on_combat_ended(), gated on _arrived_via_handoff, plus the Event Log
# button/panel toggle. Mirrors tests/test_combat_loot.gd's handoff-vs-standalone shape.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_event_log.gd

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
	CombatHandoff.event_log_entries = [] as Array[Dictionary]

	# --- Handoff-path win logs Won/XP/Loot, and the panel/button toggle works ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"EventLogTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._event_log_panel != null, "combat.gd builds an EventLogPanel")
	_check(not inst._event_log_panel.visible, "the panel starts hidden")

	inst._event_log_button.pressed.emit()
	_check(inst._event_log_panel.visible, "pressing the Event Log button shows the panel")
	inst._event_log_button.pressed.emit()
	_check(not inst._event_log_panel.visible, "pressing it again hides the panel")

	var enemy_name: String = inst._enemies[0].display_name
	inst._enemies[0].loot_table = _make_stub_table("Event Log Test Drop")
	inst._enemies[0].take_damage(9999)
	inst._turn_manager.advance_turn()   # the only real enemy is dead -> ends combat as a win

	_check(CombatHandoff.event_log_entries.has({"line": "Won: %s" % enemy_name, "category": &"combat"}),
		"a handoff win logs 'Won: <enemy names>' tagged combat (got %s)" % str(CombatHandoff.event_log_entries))
	_check(CombatHandoff.event_log_entries.has({"line": "Party gained %d XP" % inst._fight_xp_gained, "category": &"combat"}),
		"a handoff win logs the XP total tagged combat")
	_check(CombatHandoff.event_log_entries.has({"line": "Looted: Event Log Test Drop", "category": &"combat"}),
		"a handoff win logs the loot tagged combat")

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch never logs (no CombatHandoff context worth logging into) ---
	CombatHandoff.clear_pending()
	CombatHandoff.event_log_entries = [] as Array[Dictionary]
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
	# is pressed. Drive that directly, same as tests/test_combat_loot.gd, so _enemies is actually
	# populated before this test touches it.
	standalone._start_combat()
	await process_frame

	standalone._enemies[0].take_damage(9999)
	standalone._turn_manager.advance_turn()
	_check(CombatHandoff.event_log_entries.is_empty(), "a standalone (non-handoff) fight never logs to the event log")

	standalone.queue_free()
	await process_frame

	print(("COMBAT EVENT LOG TEST PASSED" if _failures == 0 else "COMBAT EVENT LOG TEST FAILED: %d" % _failures))
	quit(_failures)
