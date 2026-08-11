extends SceneTree

## Real-scene test: opening the Adventuring Board completes the tutorial's new "visit_board"
## objective (player-requested — the tutorial's original 8 steps never mentioned the board's real
## functionality: Party Selection, "Level Up to Endgame"). Mirrors the interaction-driven objectives
## already covered by test_town_demo.gd-style scene tests.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var tutorial: Quest = QuestLibrary.get_quest(&"tutorial")
	var ids: Array[StringName] = []
	for objective: QuestObjective in tutorial.objectives:
		ids.append(objective.id)
	_check(ids.has(&"visit_board"), "the tutorial quest has a visit_board objective")
	_check(ids.find(&"visit_board") > ids.find(&"visit_shop"), "visit_board comes after visit_shop")
	_check(ids.find(&"visit_board") < ids.find(&"win_fight"), "visit_board comes before win_fight")

	var scene: PackedScene = load("res://world/town_demo.tscn")
	var demo: TownDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	_check(not demo._party_inventory.is_objective_complete(&"tutorial", &"visit_board"), "visit_board starts incomplete on a fresh town_demo load")
	demo._on_board_opened(demo._make_quest_entries())
	await process_frame
	_check(demo._party_inventory.is_objective_complete(&"tutorial", &"visit_board"), "opening the Adventuring Board completes visit_board")

	quit()
