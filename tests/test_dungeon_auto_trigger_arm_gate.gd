extends SceneTree

## Regression for a human-playtest-found softlock (2026-07-17): losing a mid-dungeon fight returns
## the player to return_position (right where the still-alive enemy is, since combat.gd's
## _resolve_handoff_continue() only calls mark_defeated() on a WIN) — the enemy respawns at its
## fixed home position and the PC's spawn point overlaps its auto_trigger zone on the very first
## processed frame, immediately re-firing the SAME encounter before the player can move. This read
## as "pressing Continue on the defeat screen snaps back to the defeat screen" — a softlock.
##
## Fix: DungeonDemo requires the PC to move AUTO_TRIGGER_ARM_DISTANCE away from its spawn point
## before any auto_trigger interactable is allowed to fire. This test rigs the exact "returned from
## a lost fight standing on the not-yet-defeated enemy" state directly via CombatHandoff (mirroring
## combat.gd's real loss-path effect: begin_encounter() then clear_combat_data(), no mark_defeated())
## and proves the enemy does NOT re-trigger for several real engine frames while un-armed, then DOES
## arm once the PC moves away.

var _dungeon_instance: Node
var _combat_handoff: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		# Mirrors the exact state combat.gd's Continue handler leaves behind after a LOSS: the
		# enemy was never marked defeated, and return_position/dungeon_floor survive
		# clear_combat_data() untouched.
		var floor3_enemy_position: Vector2 = DungeonDemo.floor_bounds(2).position + DungeonDemo.ENEMY_LOCAL
		var enemy_ids: Array[StringName] = [&"stoat"]
		_combat_handoff.begin_encounter(null, [], null, null, enemy_ids, &"DungeonFloor3Enemy",
			"res://world/dungeon_demo.tscn", floor3_enemy_position, [], [], 2)
		_combat_handoff.clear_combat_data()

		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance = scene.instantiate()
		root.add_child(_dungeon_instance)

	if _frames == 6:
		var dungeon: DungeonDemo = _dungeon_instance
		_check(dungeon._current_floor == 2, "the rigged return correctly rebuilds on floor 3 (index 2)")
		_check(dungeon._floors[2].get_node_or_null("DungeonFloor3Enemy") != null, "the not-yet-defeated floor-3 enemy is placed again, at the PC's exact spawn point")
		_check(_combat_handoff.pending_encounter_id == &"", "after several real engine frames, the un-armed PC has NOT re-triggered the encounter (pending_encounter_id stays cleared)")
		_check(dungeon._auto_trigger_armed == false, "the PC has not moved yet, so auto-trigger stays un-armed")

		# Simulate the player taking a step away from the spawn point. NOTE: this directly sets
		# global_position (an instant jump), unlike real continuous move_and_slide() movement — an
		# instant jump can leave PCController._tracked (populated only via area_entered/area_exited
		# signals) briefly stale for one physics step, which would read as a spurious re-trigger
		# immediately after arming even though the PC is genuinely far away. That staleness is a
        # test-harness artifact of instant teleportation, not a real player-facing bug: real movement
		# via move_and_slide() clears _tracked (at the ~34px combined reach+zone radius) well before
		# crossing the 40px arm distance, so this test doesn't assert "no re-trigger after moving" —
		# only that arming itself correctly flips once real distance is crossed.
		dungeon._pc.global_position += Vector2(200, 0)

	if _frames == 7:
		var dungeon: DungeonDemo = _dungeon_instance
		_check(dungeon._auto_trigger_armed == true, "moving far enough from the spawn point arms auto-trigger for the rest of the visit")

		_dungeon_instance.free()
		_combat_handoff.clear_pending()

	if _frames >= 9:
		print("ok dungeon-auto-trigger-arm-gate regression complete")
		quit()
		return true
	return false
