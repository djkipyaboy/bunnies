# tests/test_town_demo_legend.gd
extends SceneTree

## Headless smoke test: Interactable Legend opens/closes in town_demo.tscn, completes the
## tutorial's open_legend objective, and is mutually exclusive with Professions (2026-08-10
## quest-popups-and-tutorial-wiring plan Task 5). Mirrors test_town_demo_quest_log.gd's convention.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	inv.accept_quest(&"tutorial")

	_check(scene._legend_panel != null, "town_demo builds an InteractableLegendPanel")
	_check(not scene._legend_panel.is_open(), "Legend starts closed")

	scene._toggle_legend()
	_check(scene._legend_panel.is_open(), "_toggle_legend() opens the panel")
	_check(inv.is_objective_complete(&"tutorial", &"open_legend"), "opening the Legend completes the tutorial's open_legend objective")

	scene._toggle_legend()
	_check(not scene._legend_panel.is_open(), "_toggle_legend() again closes the panel")

	scene._toggle_legend()
	scene._toggle_professions()
	_check(scene._legend_panel.is_open(), "opening Professions while the Legend is open is blocked (Legend stays open)")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	# Legend is still open here (the Professions attempt above was blocked, not toggled) --
	# no extra _toggle_legend() call needed before testing the Quest Log block.
	scene._toggle_quest_log()
	_check(not scene._quest_log_panel.is_open(), "opening the Quest Log while the Legend is open is blocked")

	scene._toggle_legend()
	_check(not scene._legend_panel.is_open(), "closing the Legend at end of test leaves it closed")

	quit()
