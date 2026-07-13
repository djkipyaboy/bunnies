extends SceneTree

## Regression for the 2026-07-12 human-playtest-found bug: CombatHandoff.begin_encounter() had no
## bench param, so the bench of recruitable companions silently reset to [] after the FIRST real
## combat encounter — invisible to tests/test_shared_party_state.gd, which only exercises
## SceneExit's stash_party() (a plain scene transition), never an actual OverworldEnemy encounter.
## This drives the real sequence: recruit a companion (leaving others on the bench) -> leave town ->
## trigger a real OverworldEnemy encounter (OverworldEnemy._begin_handoff(), same as
## tests/test_overworld_enemy.gd) -> simulate the win-and-return (CombatHandoff.clear_combat_data(),
## same as combat.gd's Continue handler) -> a fresh overworld_demo.tscn instance must still see the
## REMAINING bench companions, not an emptied bench.

var _combat_handoff: Node
var _town_instance: Node
var _overworld_instance: Node
var _overworld_instance_2: Node
var _remaining_bench_names: Array[String] = []
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		var town: TownDemo = _town_instance
		_check(town._bench.size() >= 2, "the demo seeds a bench with at least 2 precreated companions")

		# Recruit exactly one companion, leaving the rest on the bench — the exact scenario the
		# player hit (they recruited the Seer, leaving vanguard/chancer/ranger/warden behind).
		var recruit: Combatant = town._bench[0]
		town._on_add_companion_requested(recruit)
		for c: Combatant in town._bench:
			_remaining_bench_names.append(c.display_name)
		_check(_remaining_bench_names.size() >= 1, "at least one companion remains on the bench after recruiting")

		town._town_exit._stash_party()

	if _frames == 2:
		var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = overworld_scene.instantiate()
		root.add_child(_overworld_instance)

		var overworld: OverworldDemo = _overworld_instance
		var current_names: Array[String] = []
		for c: Combatant in overworld._bench:
			current_names.append(c.display_name)
		_check(current_names == _remaining_bench_names, "the overworld's bench matches what was left after recruiting, before any combat")

		# Trigger a REAL OverworldEnemy encounter (mirrors test_overworld_enemy.gd) — this is the
		# exact call that used to silently reset CombatHandoff.bench to [].
		var enemy_node: OverworldEnemy = overworld._world.get_node("OverworldRat")
		enemy_node._begin_handoff()
		_check(_combat_handoff.bench.size() == _remaining_bench_names.size(), "triggering a real encounter carries the CURRENT bench into CombatHandoff, not an empty one")

		# Simulate combat.gd's Continue-on-win handler: mark defeated, then clear_combat_data()
		# ONLY (never clear_pending()) — mirrors _resolve_handoff_continue() exactly.
		_combat_handoff.mark_defeated(_combat_handoff.pending_encounter_id)
		_combat_handoff.clear_combat_data()
		_check(_combat_handoff.bench.size() == _remaining_bench_names.size(), "clear_combat_data() leaves bench intact for the overworld to reuse")

	if _frames == 3:
		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance_2 = scene.instantiate()
		root.add_child(_overworld_instance_2)

		var overworld_2: OverworldDemo = _overworld_instance_2
		var returned_names: Array[String] = []
		for c: Combatant in overworld_2._bench:
			returned_names.append(c.display_name)
		_check(returned_names == _remaining_bench_names, "after returning from combat, the bench still contains the same remaining companions (the playtest-found bug: this used to come back empty)")

		_town_instance.free()
		_overworld_instance.free()
		_overworld_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 6:
		print("ok bench-survives-combat regression complete")
		return true
	return false
