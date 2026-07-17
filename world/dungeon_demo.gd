class_name DungeonDemo
extends Node2D

## Root scene for the 4-floor dungeon prototype (2026-07-17-dungeon-scene-structure-design.md). One
## scene, 4 sibling floor containers in disjoint world-space regions (spec §3.1 — hiding a region via
## visible=false/PROCESS_MODE_DISABLED does NOT disable Godot physics collision, a previously-shipped
## Critical bug in this codebase's town prototype), toggled the same way Door toggles its 2 areas.

const FLOOR_COUNT: int = 4
const FLOOR_SIZE := Vector2(800, 600)
const FLOOR_GAP: float = 200.0
const STAIRS_DOWN_LOCAL := Vector2(700, 100)
const STAIRS_UP_LOCAL := Vector2(100, 500)
const ENEMY_LOCAL := Vector2(400, 300)
const ENTRANCE_LOCAL := Vector2(100, 500)
const FLOOR_ENEMY_IDS: Array[StringName] = [&"rat", &"ferret", &"stoat"]

var _floors: Array[Node2D] = []
var _current_floor: int = 0
var _pc: Node2D
var _camera: Camera2D
var _fade_overlay: FadeOverlay
var _dungeon_exit: SceneExit
var _interact_prompt: InteractPrompt
var _inventory_panel: InventoryMenuPanel
var _event_log_panel: EventLogPanel
var _pickup_debug_label: Label
var _highlighted_target: Interactable

var _pc_combatant: Combatant
var _companions: Array = []
var _bench: Array = []
var _shop_stock: Array = []
var _party_inventory: PartyInventory
var _vault: Vault

## Fetches the CombatHandoff autoload by path rather than referencing it as a bare global
## identifier — see OverworldEnemy._handoff()'s identical rationale (bare identifier fails under
## headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")

static func floor_bounds(index: int) -> Rect2:
	var col: int = index % 2
	var row: int = index / 2
	return Rect2(col * (FLOOR_SIZE.x + FLOOR_GAP), row * (FLOOR_SIZE.y + FLOOR_GAP), FLOOR_SIZE.x, FLOOR_SIZE.y)

func _build_floors() -> void:
	for i in range(FLOOR_COUNT):
		var bounds: Rect2 = floor_bounds(i)
		var container := Node2D.new()
		container.name = "Floor%d" % (i + 1)
		container.y_sort_enabled = true
		add_child(container)
		_floors.append(container)

		var ground := ColorRect.new()
		ground.color = Color(0.35 - i * 0.05, 0.35 - i * 0.05, 0.4 - i * 0.03)
		ground.position = bounds.position
		ground.size = bounds.size
		container.add_child(ground)
		WorldGeometry.add_boundary_walls(container, bounds)

		if i > 0:
			_place_stairs(container, bounds, i, false)
		if i < FLOOR_COUNT - 1:
			_place_stairs(container, bounds, i, true)
		if i == 0:
			_dungeon_exit = _build_dungeon_exit(container, bounds)

		container.visible = (i == _current_floor)
		container.process_mode = Node.PROCESS_MODE_INHERIT if i == _current_floor else Node.PROCESS_MODE_DISABLED

func _place_stairs(container: Node2D, bounds: Rect2, floor_index: int, going_down: bool) -> void:
	var stairs := Stairs.new()
	stairs.name = "StairsDown" if going_down else "StairsUp"
	stairs.prompt_text = "Descend" if going_down else "Ascend"
	stairs.target_floor_index = floor_index + 1 if going_down else floor_index - 1
	stairs.target_local_entry = STAIRS_UP_LOCAL if going_down else STAIRS_DOWN_LOCAL
	stairs.global_position = bounds.position + (STAIRS_DOWN_LOCAL if going_down else STAIRS_UP_LOCAL)
	stairs.dungeon = self
	container.add_child(stairs)

func _build_dungeon_exit(container: Node2D, bounds: Rect2) -> SceneExit:
	var exit := SceneExit.new()
	exit.name = "DungeonExit"
	exit.prompt_text = "Leave Dungeon"
	exit.target_scene_path = "res://world/overworld_demo.tscn"
	exit.global_position = bounds.position + ENTRANCE_LOCAL + Vector2(0, -40)
	exit.fade_overlay = _fade_overlay
	container.add_child(exit)
	return exit

func travel_to_floor(target_index: int, target_local_entry: Vector2) -> void:
	await _fade_overlay.fade_out()
	_apply_floor_change(target_index, target_local_entry)
	_fade_overlay.fade_in()

func _apply_floor_change(target_index: int, target_local_entry: Vector2) -> void:
	_floors[_current_floor].visible = false
	_floors[_current_floor].process_mode = Node.PROCESS_MODE_DISABLED
	_floors[target_index].visible = true
	_floors[target_index].process_mode = Node.PROCESS_MODE_INHERIT
	_pc.reparent(_floors[target_index], true)
	var bounds: Rect2 = floor_bounds(target_index)
	_pc.global_position = bounds.position + target_local_entry
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_camera.reset_smoothing()
	_current_floor = target_index
