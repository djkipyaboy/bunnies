extends SceneTree

## Headless regression test for CagedCat's no-respawn-on-rebuild behavior (spec 2026-07-19 §3.4),
## mirroring the established RewardPickup/GatheringNode no-respawn technique in
## tests/test_overworld_demo_npcs.gd: mark the pickup's node name defeated via
## CombatHandoff.mark_defeated() BEFORE a fresh scene load, then confirm _place_caged_cat() skips
## re-placing it on that fresh instance.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

var _instance: Node
var _frames: int = 0
var _combat_handoff: Node

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		# CombatHandoff is an autoload; it isn't reachable yet from _init(), so this setup happens
		# on the first processed frame instead (confirmed pattern — get_root().get_node()
		# succeeds here where it failed during _init()).
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()
		# A fresh Array literal, not a reused reference — mark_defeated() appends to whatever
		# backing array is assigned, and reusing the same array across an assignment + append
		# would alias, making a later reset a no-op (GDScript Arrays are reference types).
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]
		_combat_handoff.mark_defeated(&"WhiskersPickup")

		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_instance = scene.instantiate()
		root.add_child(_instance)
	if _frames == 2:
		var dungeon: DungeonDemo = _instance
		_check(dungeon._floors[3].get_node_or_null("WhiskersPickup") == null,
			"an already-rescued WhiskersPickup is skipped on scene rebuild")
		_instance.free()
		_combat_handoff.clear_pending()
	if _frames >= 3:
		print(("WHISKERS NO-RESPAWN TEST PASSED" if _failures == 0 else "WHISKERS NO-RESPAWN TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
