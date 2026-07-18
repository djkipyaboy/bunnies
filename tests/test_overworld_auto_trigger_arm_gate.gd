extends SceneTree

## Regression mirroring tests/test_dungeon_auto_trigger_arm_gate.gd's exact bug for the overworld
## (2026-07-17): the identical latent softlock risk exists here too — losing a fight against an
## OverworldEnemy returns the PC to return_position (right where the still-alive enemy is) and the
## respawned enemy's auto_trigger zone can overlap the PC's spawn point on the very first processed
## frame. Proves the same AUTO_TRIGGER_ARM_DISTANCE gate applies to overworld_demo.gd too.

var _overworld_instance: Node
var _combat_handoff: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		# Mirrors the exact state combat.gd's Continue handler leaves behind after a LOSS against
		# the overworld's own placed rat (OverworldRat, at (800, 400) per overworld_demo.gd).
		var enemy_ids: Array[StringName] = [&"rat"]
		_combat_handoff.begin_encounter(null, [], null, null, enemy_ids, &"OverworldRat",
			"res://world/overworld_demo.tscn", Vector2(800, 400))
		_combat_handoff.clear_combat_data()

		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = scene.instantiate()
		root.add_child(_overworld_instance)

	if _frames == 6:
		var overworld: OverworldDemo = _overworld_instance
		# Distance check, not strict equality — the PC and the still-alive rat both have physical
		# colliders and were placed at the exact same point, so Godot's own collision resolution
		# nudges them apart over a few physics frames; that drift is expected and irrelevant to what
		# this test proves.
		_check(overworld._pc.global_position.distance_to(Vector2(800, 400)) < 20.0, "the rigged return spawns the PC at (near) the fought enemy's position")
		_check(_combat_handoff.pending_encounter_id == &"", "after several real engine frames, the un-armed PC has NOT re-triggered the encounter")
		_check(overworld._auto_trigger_armed == false, "the PC has not moved yet, so auto-trigger stays un-armed")

		_overworld_instance.free()
		_combat_handoff.clear_pending()

	if _frames >= 8:
		print("ok overworld-auto-trigger-arm-gate regression complete")
		quit()
		return true
	return false
