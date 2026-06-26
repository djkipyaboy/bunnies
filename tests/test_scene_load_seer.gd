extends SceneTree

# Headless smoke test: combat.tscn instantiates and runs a few frames as the Seer without script/runtime
# errors (the start overlay is up; BEGIN FIGHT isn't pressed). Catches type-picker / panel wiring regressions.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_scene_load_seer.gd

func _initialize() -> void:
	Combat._pc_class_id = &"seer"   # build the scene as the Seer
	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Node = scene.instantiate()
	get_root().add_child(inst)
	# Let _ready + the deferred relayout run.
	await process_frame
	await process_frame
	await process_frame
	var ok: bool = is_instance_valid(inst) and inst is Combat
	print("  ok: combat.tscn built as Seer" if ok else "  FAIL: combat.tscn did not build")
	print(("SCENE LOAD SEER TEST PASSED" if ok else "SCENE LOAD SEER TEST FAILED: 1"))
	quit(0 if ok else 1)
