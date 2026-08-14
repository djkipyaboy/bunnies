extends SceneTree

# Headless regression test: a LOSS must NOT mark any encounter defeated (so not-yet-cleared
# content stays fightable on a later visit, exactly as before this plan), must NOT touch any
# already-defeated encounter's flag (so permanently-cleared content, including one-time pickups
# gated on it, stays cleared), and must NOT touch quest progress or quest items at all
# (2026-08-13 defeat-handling spec §4). This locks in a planning-time finding: none of this needed
# new production code, since it already falls out of CombatHandoff.is_defeated()'s existing
# gating convention (a loss never calls mark_defeated()) plus PartyInventory quest state simply
# never being touched by the combat-continue path.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_defeat_world_state_preserved.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# An already-cleared encounter (e.g. a previously-beaten floor/boss) stays cleared.
	CombatHandoff.mark_defeated(&"DungeonFloor1Enemy")
	_check(CombatHandoff.is_defeated(&"DungeonFloor1Enemy"), "sanity: floor 1 starts marked defeated")

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.accept_quest(&"tutorial")
	var quest_key: QuestItem = QuestItem.new()
	quest_key.item_id = &"dungeon_key"
	quest_key.display_name = "Rusty Key"
	inv.give_quest_item(quest_key)
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"stoat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"DungeonFloor3Enemy", "res://world/dungeon_demo.tscn", Vector2(1.0, 1.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	inst._last_result_won = false
	inst.press_continue_for_test()

	# The floor that was NOT yet cleared (the one that just defeated the player) stays not-defeated,
	# so it's still fightable on the next visit -- exactly as it already was before pressing Continue.
	_check(not CombatHandoff.is_defeated(&"DungeonFloor3Enemy"), "the not-yet-cleared floor that defeated the player is still not marked defeated after Continue")
	# An UNRELATED already-cleared floor from an earlier successful run is untouched.
	_check(CombatHandoff.is_defeated(&"DungeonFloor1Enemy"), "an already-cleared floor stays cleared (its flag is never touched by a loss)")
	# Quest progress/items are untouched.
	_check(inv.has_accepted_quest(&"tutorial"), "quest acceptance survives a loss")
	_check(inv.has_quest_item(&"dungeon_key"), "a previously-collected quest item survives a loss")

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("DEFEAT WORLD STATE PRESERVED TEST PASSED" if _failures == 0 else "DEFEAT WORLD STATE PRESERVED TEST FAILED: %d" % _failures))
	quit(_failures)
