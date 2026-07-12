extends SceneTree

# Headless test: CombatHandoff autoload (spec 2026-07-11-overworld-combat-handoff-design.md §3.1).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff.gd
#
# CombatHandoff is registered as an autoload in project.godot, but an `extends SceneTree` headless
# test script does NOT get the same autoload injection a normal scene does — referencing the bare
# identifier `CombatHandoff` fails to compile ("Identifier not found"). Approach (b) works instead:
# fetch the autoload node explicitly via get_root().get_node("CombatHandoff") once the tree exists.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")

	# --- begin_encounter() sets every field ---
	var pc: Combatant = Combatant.new()
	var comp1: Combatant = Combatant.new()
	var companions: Array = [comp1]
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat", &"ferret"]
	var encounter_id: StringName = &"OverworldRat"
	var scene_path: String = "res://world/overworld_demo.tscn"
	var position: Vector2 = Vector2(123.0, 456.0)

	CombatHandoff.begin_encounter(pc, companions, inv, vault, enemy_ids, encounter_id, scene_path, position)

	_check(CombatHandoff.pc == pc, "begin_encounter sets pc")
	_check(CombatHandoff.companions == companions, "begin_encounter sets companions")
	_check(CombatHandoff.party_inventory == inv, "begin_encounter sets party_inventory")
	_check(CombatHandoff.vault == vault, "begin_encounter sets vault")
	_check(CombatHandoff.enemy_ids == enemy_ids, "begin_encounter sets enemy_ids")
	_check(CombatHandoff.pending_encounter_id == encounter_id, "begin_encounter sets pending_encounter_id")
	_check(CombatHandoff.return_scene_path == scene_path, "begin_encounter sets return_scene_path")
	_check(CombatHandoff.return_position == position, "begin_encounter sets return_position")
	_check(CombatHandoff.has_return_position == true, "begin_encounter sets has_return_position true")

	# --- mark_defeated() / is_defeated() round-trip ---
	_check(CombatHandoff.is_defeated(&"NeverMarked") == false, "an id never marked reads false")
	CombatHandoff.mark_defeated(&"OverworldRat")
	_check(CombatHandoff.is_defeated(&"OverworldRat") == true, "a marked id reads true")
	CombatHandoff.mark_defeated(&"OverworldRat")
	var count: int = 0
	for id: StringName in CombatHandoff.defeated_encounter_ids:
		if id == &"OverworldRat":
			count += 1
	_check(count == 1, "marking the same id twice does not duplicate the array")

	# --- clear_pending() resets pending fields but NOT defeated_encounter_ids ---
	CombatHandoff.clear_pending()
	_check(CombatHandoff.pc == null, "clear_pending resets pc")
	_check(CombatHandoff.companions == [], "clear_pending resets companions")
	_check(CombatHandoff.party_inventory == null, "clear_pending resets party_inventory")
	_check(CombatHandoff.vault == null, "clear_pending resets vault")
	_check(CombatHandoff.enemy_ids == [], "clear_pending resets enemy_ids")
	_check(CombatHandoff.pending_encounter_id == &"", "clear_pending resets pending_encounter_id")
	_check(CombatHandoff.return_scene_path == "", "clear_pending resets return_scene_path")
	_check(CombatHandoff.return_position == Vector2.ZERO, "clear_pending resets return_position")
	_check(CombatHandoff.has_return_position == false, "clear_pending resets has_return_position")
	_check(CombatHandoff.is_defeated(&"OverworldRat") == true, "clear_pending does NOT clear defeated_encounter_ids")

	# --- clear_fight_data() / clear_return_position() are the split halves clear_pending() composes
	# (final-review fix, 2026-07-11): combat.gd must call ONLY clear_fight_data() before the scene
	# change, so the destination scene can still read return_position/has_return_position
	# afterward — clearing them too early was the Critical bug the review caught. ---
	CombatHandoff.begin_encounter(pc, companions, inv, vault, enemy_ids, encounter_id, scene_path, position)
	CombatHandoff.clear_fight_data()
	_check(CombatHandoff.pc == null, "clear_fight_data resets pc")
	_check(CombatHandoff.return_scene_path == "", "clear_fight_data resets return_scene_path")
	_check(CombatHandoff.return_position == position, "clear_fight_data leaves return_position untouched")
	_check(CombatHandoff.has_return_position == true, "clear_fight_data leaves has_return_position untouched")

	CombatHandoff.clear_return_position()
	_check(CombatHandoff.return_position == Vector2.ZERO, "clear_return_position resets return_position")
	_check(CombatHandoff.has_return_position == false, "clear_return_position resets has_return_position")

	print(("COMBAT HANDOFF TEST PASSED" if _failures == 0 else "COMBAT HANDOFF TEST FAILED: %d" % _failures))
	quit(_failures)
