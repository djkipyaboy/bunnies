extends SceneTree

# Headless test: CombatHandoff.last_town_scene_path tracks the last town scene the player actually
# visited (2026-08-13 defeat-handling spec §4) — a real town_demo.tscn instance sets it on _ready(),
# and it survives a combat round-trip's clear_combat_data()/clear_party() calls (same persistence
# convention as defeated_encounter_ids/unlocked_gate_ids).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_last_town.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	_check(CombatHandoff.last_town_scene_path == "res://world/town_demo.tscn", "defaults to the only existing town before any town has (re-)set it this run")

	# A real town_demo.tscn instance sets it on _ready().
	CombatHandoff.last_town_scene_path = ""  # force a non-default value first, so the next check is meaningful
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	var town_instance: Node = town_scene.instantiate()
	root.add_child(town_instance)
	await process_frame

	_check(CombatHandoff.last_town_scene_path == "res://world/town_demo.tscn", "town_demo.gd's _ready() sets last_town_scene_path")

	# Survives clear_combat_data()/clear_party() (a combat round-trip), unlike return_scene_path.
	CombatHandoff.clear_combat_data()
	CombatHandoff.clear_party()
	_check(CombatHandoff.last_town_scene_path == "res://world/town_demo.tscn", "last_town_scene_path survives clear_combat_data()/clear_party()")

	town_instance.free()
	CombatHandoff.clear_pending()

	print(("COMBAT HANDOFF LAST TOWN TEST PASSED" if _failures == 0 else "COMBAT HANDOFF LAST TOWN TEST FAILED: %d" % _failures))
	quit(_failures)
