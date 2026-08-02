extends SceneTree

## Confirms both gathering-panel positions are updated to center their now-doubled (2x scale)
## footprint on the game's actual 1600x900 window (2026-08-02 gathering-reel-colors-and-sizing spec
## section 4), in the real overworld scene.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	_check(demo._foraging_panel.position == Vector2(440, 228), "ForagingPanel is centered for its 720x444 (2x-scaled) footprint in a 1600x900 window")
	_check(demo._fishing_panel.position == Vector2(280, 10), "FishingPanel is centered for its 1040x880 (2x-scaled) footprint in a 1600x900 window")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	quit()
