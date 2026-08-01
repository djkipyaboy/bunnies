extends SceneTree

## Headless test: the Town Adventuring Board's "Test: Hollow Warden Fight" debug button maxes the
## party's jackpot meter and populates CombatHandoff with a real Hollow Warden encounter, tagged
## with the same &"DungeonFloor4Enemy" id the real dungeon floor uses. Player request, 2026-08-01:
## skip the ~30-minute walk through dungeon floors 1-3 for boss-fight testing.

var _town: TownDemo
var _combat_handoff: Node
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_town = scene.instantiate() as TownDemo
	root.add_child(_town)
	await process_frame
	await process_frame

	_combat_handoff = get_root().get_node("CombatHandoff")
	_combat_handoff.clear_pending()
	_town._party_inventory.jackpot_meter = 10  # below cap, so the fix is provably doing the work

	_town._on_board_opened([])   # real production entry point, same as the endgame-level-up test
	_check(_town._board_panel.visible, "the real Adventuring Board opens")
	_town._board_panel.press_test_boss_fight_for_test()

	_check(_combat_handoff.pc == _town._pc_combatant, "CombatHandoff.pc is the real, currently-assembled PC")
	_check(_combat_handoff.companions == _town._companions, "CombatHandoff.companions is the real, currently-assembled companion list")
	_check(_combat_handoff.enemy_ids == [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"], "enemy_ids is the real Hollow Warden trio (got %s)" % [_combat_handoff.enemy_ids])
	_check(_combat_handoff.pending_encounter_id == &"DungeonFloor4Enemy", "tagged with the SAME encounter id the real dungeon floor uses, so a win marks the real boss defeated")
	_check(_combat_handoff.return_scene_path == "res://world/town_demo.tscn", "returns to town, not the dungeon")
	_check(_combat_handoff.has_return_position, "a return position is set")
	_check(_town._party_inventory.jackpot_meter == PartyInventory.JACKPOT_CAP, "jackpot meter is maxed (got %d)" % _town._party_inventory.jackpot_meter)
	_check(not _town._board_panel.visible, "the board closes after pressing the button")

	# Repeatable: pressing it again produces the identical handoff state, no crash.
	_town._on_board_opened([])
	_town._board_panel.press_test_boss_fight_for_test()
	_check(_combat_handoff.pending_encounter_id == &"DungeonFloor4Enemy", "second press: still tagged correctly")

	_town.free()
	print(("TOWN DEMO TEST BOSS FIGHT BUTTON TEST PASSED" if _failures == 0 else "TOWN DEMO TEST BOSS FIGHT BUTTON TEST FAILED: %d" % _failures))
	quit(_failures)
