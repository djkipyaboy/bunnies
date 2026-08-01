extends SceneTree

## Regression for a final-whole-branch-review finding (2026-08-01): town_demo.gd never
## consumed/cleared CombatHandoff.return_position (or pending_ground_drops) after the new debug
## "Test: Hollow Warden Fight" button (Task 5, commit 2247007) launches a fight — the FIRST time
## town_demo.tscn has ever been used as a combat return_scene_path. Every other scene that's ever
## been a return destination (overworld_demo.gd, dungeon_demo.gd) reads return_position/
## has_return_position at PC-build time and then clears it; town_demo.gd did neither.
##
## Real consequence traced end to end: press the debug button in town -> fight -> Continue ->
## combat.gd's _resolve_handoff_continue() calls CombatHandoff.clear_combat_data(), which
## DELIBERATELY preserves return_position/has_return_position for the destination scene to consume
## -> town rebuilds and never reads/clears them -> the player then walks out of town via TownExit
## into the overworld -> overworld_demo.gd's PC-build code sees has_return_position == true (still
## set from the earlier, completely unrelated debug-boss-fight transition) and spawns the PC at the
## STALE town coordinate inside overworld space instead of the correct overworld spawn point.
##
## Fix: town_demo.gd's _build_pc() now clears both fields immediately (it never needed to READ
## return_position for its own placement — it's not a scene the PC visually "arrives into" from
## combat), mirroring the same "clear once consumed/decided-irrelevant" convention used everywhere
## else in this codebase. Mirrors tests/test_dungeon_exit_spawn_position.gd's technique: instantiate
## scene A, populate CombatHandoff, instantiate scene B fresh, assert on scene B's state.
##
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_debug_boss_fight_return_position_clear.gd

var _combat_handoff: Node
var _town_instance: Node
var _overworld_instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	_combat_handoff = get_root().get_node("CombatHandoff")
	_combat_handoff.clear_pending()

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		# --- Build town_demo.tscn, press the real debug boss-fight button (real production entry
		# point, same as tests/test_town_demo_test_boss_fight.gd) ---
		var scene: PackedScene = load("res://world/town_demo.tscn")
		_town_instance = scene.instantiate()
		root.add_child(_town_instance)
		return false

	if _frames == 3:
		var town: TownDemo = _town_instance
		town._on_board_opened([])
		town._board_panel.press_test_boss_fight_for_test()
		_check(_combat_handoff.has_return_position, "sanity: begin_encounter() set a return position for town")
		# Give the returned drops something non-empty too, so clearing it is provably exercised
		# (the Hollow Warden encounter currently has no loot table, so this would otherwise always
		# be empty for this specific fight and the clear would be a no-op in practice).
		var dummy_gear: Gear = Gear.new()
		_combat_handoff.pending_ground_drops = [dummy_gear] as Array[Resource]

		# --- Simulate combat.gd's real Continue handler: it calls clear_combat_data() BEFORE the
		# scene change, deliberately preserving return_position/has_return_position/
		# pending_ground_drops for the destination scene (town_demo.tscn) to consume. ---
		_combat_handoff.clear_combat_data()
		_check(_combat_handoff.has_return_position, "clear_combat_data() deliberately preserves return_position for the destination scene")
		_check(_combat_handoff.pending_ground_drops.size() == 1, "clear_combat_data() deliberately preserves pending_ground_drops too")

		# --- Rebuild town_demo.tscn fresh (mirrors the real scene reload after Continue) — its
		# _build_pc() must now read+clear both fields. ---
		_town_instance.free()
		var scene: PackedScene = load("res://world/town_demo.tscn")
		_town_instance = scene.instantiate()
		root.add_child(_town_instance)
		return false

	if _frames == 5:
		_check(not _combat_handoff.has_return_position, "town_demo.gd's rebuild consumed and cleared has_return_position (the actual fix)")
		_check(_combat_handoff.return_position == Vector2.ZERO, "return_position itself is reset too")
		_check(_combat_handoff.pending_ground_drops.is_empty(), "town_demo.gd's rebuild also cleared pending_ground_drops")

		# --- The actual reported symptom: leaving town for the overworld right after must NOT spawn
		# the PC at a stale position — overworld_demo.gd's own _build_pc() would otherwise see
		# has_return_position == true left over from the unrelated debug-boss-fight transition. ---
		_town_instance.free()
		var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = overworld_scene.instantiate()
		root.add_child(_overworld_instance)
		return false

	if _frames == 7:
		var overworld: OverworldDemo = _overworld_instance
		var village_distance: float = overworld._pc.global_position.distance_to(OverworldDemo.VILLAGE_POSITION)
		_check(village_distance < 200.0, "the PC spawns at the overworld's normal PC_SPAWN (near the village), not a stale town coordinate (got %s, village at %s)" % [overworld._pc.global_position, OverworldDemo.VILLAGE_POSITION])

		_overworld_instance.free()
		_combat_handoff.clear_pending()
		print(("TOWN DEBUG BOSS FIGHT RETURN-POSITION CLEAR TEST PASSED" if _failures == 0 else "TOWN DEBUG BOSS FIGHT RETURN-POSITION CLEAR TEST FAILED: %d" % _failures))
		quit(_failures)
		return true

	return false
