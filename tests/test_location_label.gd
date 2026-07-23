extends SceneTree

## Headless test for the 2026-07-23 playtest feedback: a persistent corner label should show which
## location the player is currently in (Town / Overworld / Dungeon (Floor N)) — there was previously
## no on-screen indicator at all.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	var town: TownDemo = town_scene.instantiate() as TownDemo
	root.add_child(town)
	await process_frame
	await process_frame
	_check(town._location_label != null, "town_demo builds a location label")
	_check(town._location_label.text == "Town", "town_demo's location label reads 'Town'")
	town.free()

	var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
	var overworld: Node = overworld_scene.instantiate()
	root.add_child(overworld)
	await process_frame
	await process_frame
	_check(overworld._location_label != null, "overworld_demo builds a location label")
	_check(overworld._location_label.text == "Overworld", "overworld_demo's location label reads 'Overworld'")
	overworld.free()
	root.get_node("CombatHandoff").clear_pending()

	var dungeon_scene: PackedScene = load("res://world/dungeon_demo.tscn")
	var dungeon: DungeonDemo = dungeon_scene.instantiate() as DungeonDemo
	root.add_child(dungeon)
	await process_frame
	await process_frame
	_check(dungeon._location_label != null, "dungeon_demo builds a location label")
	_check(dungeon._location_label.text == "Dungeon (Floor 1)", "a fresh dungeon launch's label reads 'Dungeon (Floor 1)'")

	dungeon._apply_floor_change(2, Vector2(100, 100))
	_check(dungeon._location_label.text == "Dungeon (Floor 3)", "the label updates to 'Dungeon (Floor 3)' after descending to floor index 2")
	dungeon.free()
	root.get_node("CombatHandoff").clear_pending()

	print(("LOCATION LABEL TEST PASSED" if _failures == 0 else "LOCATION LABEL TEST FAILED: %d" % _failures))
	quit(_failures)
