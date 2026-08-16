extends SceneTree

## Regression test for a real playtest bug: "Tutorial quest skips steps if player completes the
## tasks out of order." Root cause: _toggle_stats() ('C', WoW-style character pane) opens the
## exact same InventoryMenuPanel that _toggle_inventory() ('I', the tutorial's actual instructed
## key) does — just to a different starting tab — but only _toggle_inventory()'s own open branch
## called PartyInventory.complete_objective(&"tutorial", &"open_inventory"). A player who presses
## 'C' before ever pressing 'I' (very natural — 'C' is the more familiar keybinding) leaves the
## panel already visible, so their later 'I' press only CLOSES it; that close branch never awards
## credit, silently "skipping" a step the player had, in substance, already completed. Fixed by
## crediting open_inventory from _toggle_stats()'s open branch too, in all 3 world scenes.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	# town_demo.gd
	var town: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(town)
	await process_frame
	await process_frame
	var town_inv: PartyInventory = town._party_inventory

	town._toggle_stats()
	_check(town._inventory_panel.visible, "town: inventory panel visible after Stats ('C')")
	_check(town_inv.is_objective_complete(&"tutorial", &"open_inventory"), "town: open_inventory credited by Stats alone")

	town._toggle_inventory()
	_check(not town._inventory_panel.visible, "town: pressing 'I' next just closes the already-open panel")
	_check(town_inv.is_objective_complete(&"tutorial", &"open_inventory"), "town: open_inventory stays credited")
	town.free()

	# overworld_demo.gd
	var overworld: Node = load("res://world/overworld_demo.tscn").instantiate()
	get_root().add_child(overworld)
	await process_frame
	await process_frame
	var overworld_inv: PartyInventory = overworld._party_inventory

	overworld._toggle_stats()
	_check(overworld._inventory_panel.visible, "overworld: inventory panel visible after Stats ('C')")
	_check(overworld_inv.is_objective_complete(&"tutorial", &"open_inventory"), "overworld: open_inventory credited by Stats alone")
	overworld.free()

	# dungeon_demo.gd
	var dungeon: Node = load("res://world/dungeon_demo.tscn").instantiate()
	get_root().add_child(dungeon)
	await process_frame
	await process_frame
	var dungeon_inv: PartyInventory = dungeon._party_inventory

	dungeon._toggle_stats()
	_check(dungeon._inventory_panel.visible, "dungeon: inventory panel visible after Stats ('C')")
	_check(dungeon_inv.is_objective_complete(&"tutorial", &"open_inventory"), "dungeon: open_inventory credited by Stats alone")

	quit()
