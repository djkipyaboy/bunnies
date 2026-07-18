extends SceneTree

## Regression for a human-playtest-found bug (2026-07-17): "Leave Dungeon" dropped the player off at
## the village (overworld_demo.gd's fixed PC_SPAWN) instead of near the mountain/dungeon entrance
## they actually used. Root cause: overworld_demo.gd's _build_pc() only ever special-cased
## CombatHandoff.return_position (the combat-round-trip path) — a plain SceneExit transition (the
## dungeon's own exit, or the pre-existing TownExit/VillageEntrance pair) always fell back to the
## single fixed PC_SPAWN constant, regardless of which SceneExit triggered the transition. This
## happened to look correct for the town<->overworld pair (PC_SPAWN sits right next to the village)
## but is clearly wrong for the dungeon (on the far side of the map, near the mountain).
##
## Fix: CombatHandoff gains entry_spawn_position/has_entry_spawn_position, threaded through
## stash_party()'s two new trailing params, mirroring the exact shape of return_position/
## has_return_position but for the plain-transition path. SceneExit gains target_spawn_position/
## has_target_spawn_position (settable per-instance by whoever places it), passed into
## stash_party() by _stash_party(). overworld_demo.gd's _build_pc() now checks has_return_position
## first (combat-return path, unchanged priority), then has_entry_spawn_position (new), then falls
## back to PC_SPAWN. Only the dungeon's own DungeonExit sets a target spawn this pass — the
## pre-existing VillageEntrance/TownExit pair is untouched (PC_SPAWN already reads correctly there).

var _combat_handoff: Node
var _overworld_instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	_combat_handoff = get_root().get_node("CombatHandoff")
	_combat_handoff.clear_pending()

	# --- CombatHandoff.stash_party()'s new trailing params ---
	_combat_handoff.stash_party(null, [], null, null, [], [], Vector2(1160, 260), true)
	_check(_combat_handoff.entry_spawn_position == Vector2(1160, 260), "stash_party() sets entry_spawn_position")
	_check(_combat_handoff.has_entry_spawn_position == true, "stash_party() sets has_entry_spawn_position")

	_combat_handoff.clear_entry_spawn_position()
	_check(_combat_handoff.has_entry_spawn_position == false, "clear_entry_spawn_position() resets has_entry_spawn_position")
	_check(_combat_handoff.entry_spawn_position == Vector2.ZERO, "clear_entry_spawn_position() resets entry_spawn_position")

	# stash_party()'s new params default to unset, so every pre-existing call site (which never
	# passes them) is unaffected.
	_combat_handoff.stash_party(null, [], null, null)
	_check(_combat_handoff.has_entry_spawn_position == false, "stash_party()'s target-spawn params default to unset")

	_combat_handoff.clear_pending()
	# SceneExit threading target_spawn_position through _stash_party() is proven end to end below
	# (frame 1: the real DungeonExit's _stash_party() call, verified via frame 2's spawn-position
	# checks) rather than in isolation here — a bare SceneExit not yet added to the tree can't
	# resolve _handoff()'s absolute "/root/CombatHandoff" path this early in the SceneTree lifecycle.

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		# --- The real DungeonExit's placement-time fields, end to end ---
		var dungeon_scene: PackedScene = load("res://world/dungeon_demo.tscn")
		var dungeon_instance: Node = dungeon_scene.instantiate()
		root.add_child(dungeon_instance)
		var dungeon: DungeonDemo = dungeon_instance
		_check(dungeon._dungeon_exit.has_target_spawn_position == true, "the real DungeonExit has a target spawn position set")
		_check(dungeon._dungeon_exit.target_spawn_position.distance_to(Vector2(0, 0)) > 500.0, "the DungeonExit's target spawn is nowhere near the overworld origin (i.e. it's near the mountain, not left as a default)")

		dungeon._dungeon_exit._stash_party()
		dungeon_instance.free()
		_combat_handoff.clear_party()   # _stash_party() also sets pc/companions/etc — clear those, keep the spawn fields

	if _frames == 2:
		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = scene.instantiate()
		root.add_child(_overworld_instance)

		var overworld: OverworldDemo = _overworld_instance
		var village_distance: float = overworld._pc.global_position.distance_to(OverworldDemo.VILLAGE_POSITION)
		_check(village_distance > 400.0, "the PC does NOT spawn near the village after leaving the dungeon (this was the reported bug)")
		_check(overworld._pc.global_position.distance_to(overworld.MOUNTAIN_RECT.position) < 300.0, "the PC spawns near the mountain/dungeon entrance instead")
		_check(_combat_handoff.has_entry_spawn_position == false, "the overworld consumed and cleared has_entry_spawn_position")

		_overworld_instance.free()
		_combat_handoff.clear_pending()

	if _frames >= 4:
		print("ok dungeon-exit-spawn-position regression complete")
		quit()
		return true
	return false
