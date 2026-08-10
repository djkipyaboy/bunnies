# tests/test_overworld_demo_legend.gd
extends SceneTree

## Headless smoke test: Interactable Legend in overworld_demo.tscn (2026-08-10 quest-popups-and-
## tutorial-wiring plan Task 6), mirrors test_town_demo_legend.gd.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/overworld_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	inv.accept_quest(&"tutorial")

	_check(scene._legend_panel != null, "overworld_demo builds an InteractableLegendPanel")
	_check(not scene._legend_panel.is_open(), "Legend starts closed")

	scene._toggle_legend()
	_check(scene._legend_panel.is_open(), "_toggle_legend() opens the panel")
	_check(inv.is_objective_complete(&"tutorial", &"open_legend"), "opening the Legend completes the tutorial's open_legend objective")

	scene._toggle_legend()
	_check(not scene._legend_panel.is_open(), "_toggle_legend() again closes the panel")

	scene._toggle_legend()
	scene._toggle_professions()
	_check(scene._legend_panel.is_open(), "opening Professions while the Legend is open is blocked")
	_check(not scene._professions_panel.is_open(), "Professions did not open")

	quit()
