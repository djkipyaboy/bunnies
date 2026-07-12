extends SceneTree

# Headless test: OverworldEnemy composes an auto-triggering, contact-sized Interactable and
# emits encounter_triggered (with its authored enemy_ids) then frees itself when touched.
# Spec: docs/superpowers/specs/2026-07-11-overworld-npc-encounters-design.md §3.3.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_enemy.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

var _enemy: OverworldEnemy

func _init() -> void:
	_enemy = OverworldEnemy.new()
	_enemy.enemy_ids = [&"rat"]
	root.add_child(_enemy)

func _process(_delta: float) -> bool:
	var enemy: OverworldEnemy = _enemy
	var zone: Interactable = enemy.get_node("InteractionZone")
	_check(zone != null, "OverworldEnemy composes an InteractionZone Interactable child")
	_check(zone.auto_trigger == true, "the composed Interactable has auto_trigger == true")
	_check(zone.interaction_radius == 10.0, "the composed Interactable's interaction_radius is contact-sized (10.0)")
	_check(zone.interaction_radius < 16.0, "the composed Interactable's interaction_radius is smaller than Villager's default 16.0")

	# GDScript lambdas capture outer locals BY VALUE, not by reference — a plain bool/Array
	# assigned to from inside the lambda would never be visible out here. Use a single-element
	# holder Array instead: the Array itself is a reference type, so mutating its contents
	# (not reassigning the outer var) is visible after the signal fires.
	var captured: Array = [false, []]
	enemy.encounter_triggered.connect(func(ids) -> void:
		captured[0] = true
		captured[1] = ids
	)

	zone.interact()

	_check(captured[0], "triggering the composed Interactable emits encounter_triggered")
	_check(captured[1] == [&"rat"], "encounter_triggered carries the authored enemy_ids")
	_check(enemy.is_queued_for_deletion(), "the OverworldEnemy node is queued for deletion after triggering")

	print(("OVERWORLD ENEMY TEST PASSED" if _failures == 0 else "OVERWORLD ENEMY TEST FAILED: %d" % _failures))
	quit(_failures)
	return true
