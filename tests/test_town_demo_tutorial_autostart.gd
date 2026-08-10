# tests/test_town_demo_tutorial_autostart.gd
extends SceneTree

## Headless test: a fresh town_demo.tscn load auto-accepts the tutorial quest (2026-08-10 quest-
## system-and-tutorial design §8's "auto-starts... every fresh launch" behavior).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	_check(inv.has_accepted_quest(&"tutorial"), "a fresh town_demo load auto-accepts the tutorial quest")
	_check(inv.is_quest_tracked(&"tutorial"), "the auto-accepted tutorial is tracked by default (accept_quest()'s existing behavior)")

	quit()
