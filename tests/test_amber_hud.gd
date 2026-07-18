extends SceneTree

## Headless test for the persistent Amber HUD label (2026-07-18 playtest-found gap): Amber only ever
## showed on InventoryMenuPanel's Stats tab, which the player didn't notice — town_demo.gd,
## overworld_demo.gd, and dungeon_demo.gd all gained a persistent "Amber: N" label, refreshed every
## _process() tick, at (16, 100) (clear of the existing InteractPrompt/PickupDebugLabel column).

var _town_instance: Node
var _overworld_instance: Node
var _dungeon_instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

	var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
	_overworld_instance = overworld_scene.instantiate()
	root.add_child(_overworld_instance)

	var dungeon_scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_dungeon_instance = dungeon_scene.instantiate()
	root.add_child(_dungeon_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _town_instance
		town._party_inventory.amber = 42
		var overworld: OverworldDemo = _overworld_instance
		overworld._party_inventory.amber = 7
		var dungeon: DungeonDemo = _dungeon_instance
		dungeon._party_inventory.amber = 13

	if _frames == 2:
		var town: TownDemo = _town_instance
		var overworld: OverworldDemo = _overworld_instance
		var dungeon: DungeonDemo = _dungeon_instance
		_check(town._amber_label.text == "Amber: 42", "town_demo's Amber label reflects the party's current balance")
		_check(overworld._amber_label.text == "Amber: 7", "overworld_demo's Amber label reflects the party's current balance")
		_check(dungeon._amber_label.text == "Amber: 13", "dungeon_demo's Amber label reflects the party's current balance")
		_check(town._amber_label.position == Vector2(16, 100), "the Amber label sits clear of the existing InteractPrompt/PickupDebugLabel column")

		_town_instance.free()
		_overworld_instance.free()
		_dungeon_instance.free()
		get_root().get_node("CombatHandoff").clear_pending()

	if _frames >= 4:
		print("ok amber-hud regression complete")
		quit()
		return true
	return false
