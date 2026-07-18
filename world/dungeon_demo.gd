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
const KEY_LOCAL := Vector2(600, 150)   # floor 2 (index 1); clear of its stairs (700,100)/(100,500) and enemy (400,300)
const FLOOR_ENEMY_IDS: Array[StringName] = [&"rat", &"ferret", &"stoat"]

## Playtest-found bug (2026-07-17): "Leave Dungeon" used to drop the player at the overworld's
## generic PC_SPAWN (near the village) instead of near the mountain they actually used. Must match
## overworld_demo.gd's DungeonEntranceDebug placement — MOUNTAIN_RECT.position +
## Vector2(MOUNTAIN_RECT.size.x/2.0, MOUNTAIN_RECT.size.y+20.0) = (1160, 220) — offset further south
## so the returning PC doesn't stand exactly on the entrance's own interactable.
const OVERWORLD_EXIT_SPAWN := Vector2(1160, 260)

## Playtest-found softlock (2026-07-17): losing a fight returns the PC to return_position — right
## where the still-alive enemy is, since a loss never marks it defeated — and the respawned enemy's
## auto_trigger zone overlaps the PC's spawn point on the very first processed frame, immediately
## re-firing the SAME encounter before the player can move. Requiring genuine movement away from the
## spawn point before any auto_trigger interactable can fire closes this without needing to know
## win/loss at all — a fresh scene load already spawns far from every placed enemy, so this is a
## no-op there.
const AUTO_TRIGGER_ARM_DISTANCE: float = 40.0

var _floors: Array[Node2D] = []
var _current_floor: int = 0
var _pc: PCController
var _camera: Camera2D
var _fade_overlay: FadeOverlay
var _dungeon_exit: SceneExit
var _interact_prompt: InteractPrompt
var _inventory_panel: InventoryMenuPanel
var _event_log_panel: EventLogPanel
var _pickup_debug_label: Label
var _highlighted_target: Interactable
var _spawn_position: Vector2 = Vector2.ZERO
var _auto_trigger_armed: bool = false

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

func is_gate_unlocked(gate_id: StringName) -> bool:
	return _handoff().is_gate_unlocked(gate_id)

func try_consume_quest_item(item_id: StringName) -> bool:
	return _party_inventory.consume_quest_item(item_id)

func mark_gate_unlocked(gate_id: StringName) -> void:
	_handoff().mark_gate_unlocked(gate_id)

func show_locked_message() -> void:
	_pickup_debug_label.text = "The way down is locked — you need a key."

## Playtest-found gap (2026-07-18): using the key to unlock the gate had no on-screen confirmation
## at all, unlike every other notable event in this scene (item pickups, Bag-full rejections, the
## locked message itself) — the player couldn't tell the key had actually done anything.
func show_unlocked_message() -> void:
	_pickup_debug_label.text = "The Rusty Key unlocks the way down!"

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
			if i == 2:
				_place_stairs(container, bounds, i, true, &"dungeon_key", &"dungeon_floor3_to_4_gate")
			else:
				_place_stairs(container, bounds, i, true)
		if i == 0:
			_dungeon_exit = _build_dungeon_exit(container, bounds)

		container.visible = (i == _current_floor)
		container.process_mode = Node.PROCESS_MODE_INHERIT if i == _current_floor else Node.PROCESS_MODE_DISABLED

func _place_stairs(container: Node2D, bounds: Rect2, floor_index: int, going_down: bool,
		required_quest_item_id: StringName = &"", gate_id: StringName = &"") -> void:
	var stairs := Stairs.new()
	stairs.name = "StairsDown" if going_down else "StairsUp"
	stairs.prompt_text = "Descend" if going_down else "Ascend"
	stairs.target_floor_index = floor_index + 1 if going_down else floor_index - 1
	stairs.target_local_entry = STAIRS_UP_LOCAL if going_down else STAIRS_DOWN_LOCAL
	stairs.global_position = bounds.position + (STAIRS_DOWN_LOCAL if going_down else STAIRS_UP_LOCAL)
	stairs.dungeon = self
	stairs.required_quest_item_id = required_quest_item_id
	stairs.gate_id = gate_id
	container.add_child(stairs)

	# Playtest-found UX gap (2026-07-17): stairs sat on flat, featureless ground with zero visual
	# indicator. A stone-gray arrow (distinct from the yellow scene-exit arrows below), pointing
	# down for a descent, up for an ascent.
	var arrow := Polygon2D.new()
	arrow.name = "StairsArrow"
	arrow.color = Color(0.55, 0.55, 0.6)
	arrow.modulate.a = Interactable.DIM_ALPHA
	arrow.polygon = PackedVector2Array([
		Vector2(-4, -15), Vector2(4, -15), Vector2(4, 5),
		Vector2(10, 5), Vector2(0, 20), Vector2(-10, 5), Vector2(-4, 5),
	]) if going_down else PackedVector2Array([
		Vector2(-4, 15), Vector2(4, 15), Vector2(4, -5),
		Vector2(10, -5), Vector2(0, -20), Vector2(-10, -5), Vector2(-4, -5),
	])
	stairs.add_child(arrow)
	stairs.highlight_visual = arrow

func _build_dungeon_exit(container: Node2D, bounds: Rect2) -> SceneExit:
	var exit := SceneExit.new()
	exit.name = "DungeonExit"
	exit.prompt_text = "Leave Dungeon"
	exit.target_scene_path = "res://world/overworld_demo.tscn"
	exit.global_position = bounds.position + ENTRANCE_LOCAL + Vector2(0, -40)
	exit.fade_overlay = _fade_overlay
	exit.target_spawn_position = OVERWORLD_EXIT_SPAWN
	exit.has_target_spawn_position = true
	container.add_child(exit)

	# Same yellow scene-exit arrow convention as town_demo.gd's TownExit/ExitDoor (playtest-found
	# UX gap, 2026-07-17 — the dungeon exit sat on flat ground with no visual indicator at all).
	var arrow := Polygon2D.new()
	arrow.name = "DungeonExitArrow"
	arrow.color = Color(1.0, 0.95, 0.4)
	arrow.modulate.a = Interactable.DIM_ALPHA
	arrow.polygon = PackedVector2Array([
		Vector2(-4, -15), Vector2(4, -15), Vector2(4, 5),
		Vector2(10, 5), Vector2(0, 20), Vector2(-10, 5), Vector2(-4, 5),
	])
	exit.add_child(arrow)
	exit.highlight_visual = arrow

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

func _ready() -> void:
	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)
	var start: Dictionary = _determine_start()
	_current_floor = start["floor"]
	_build_floors()
	_build_pc(start["position"])
	_build_camera()
	_build_ui()
	_build_inventory_demo()
	_place_dungeon_enemies()
	_place_dungeon_key()
	_dungeon_exit.pc_combatant = _pc_combatant
	_dungeon_exit.companions = _companions
	_dungeon_exit.bench = _bench
	_dungeon_exit.party_inventory = _party_inventory
	_dungeon_exit.vault = _vault
	_dungeon_exit.shop_stock = _shop_stock

func _determine_start() -> Dictionary:
	var handoff: Node = _handoff()
	if handoff.has_return_position:
		var result: Dictionary = {"floor": handoff.dungeon_floor, "position": handoff.return_position}
		handoff.clear_return_position()
		return result
	return {"floor": 0, "position": floor_bounds(0).position + ENTRANCE_LOCAL}

func _build_pc(start_position: Vector2) -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	_pc.global_position = start_position
	_spawn_position = start_position

	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 8.0
	capsule.height = 20.0
	shape.shape = capsule
	_pc.add_child(shape)

	var visual := ColorRect.new()
	visual.color = Color(0.85, 0.55, 0.25)
	visual.position = Vector2(-8, -12)
	visual.size = Vector2(16, 24)
	_pc.add_child(visual)

	_floors[_current_floor].add_child(_pc)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	var bounds: Rect2 = floor_bounds(_current_floor)
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_pc.add_child(_camera)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	_interact_prompt = InteractPrompt.new()
	_interact_prompt.position = Vector2(16, 16)
	ui.add_child(_interact_prompt)

	_inventory_panel = InventoryMenuPanel.new()
	_inventory_panel.position = Vector2(140, 60)
	_inventory_panel.hide()
	ui.add_child(_inventory_panel)
	_inventory_panel.item_discarded.connect(_on_item_discarded)

	_pickup_debug_label = Label.new()
	_pickup_debug_label.name = "PickupDebugLabel"
	_pickup_debug_label.position = Vector2(16, 70)
	_pickup_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	ui.add_child(_pickup_debug_label)

	_event_log_panel = EventLogPanel.new()
	_event_log_panel.position = Vector2(880, 500)
	_event_log_panel.visible = false
	ui.add_child(_event_log_panel)
	_event_log_panel.build()
	_event_log_panel.refresh(_handoff().event_log_entries)
	_handoff().event_logged.connect(_event_log_panel.append_line)

func _build_inventory_demo() -> void:
	var handoff: Node = _handoff()
	if handoff.pc != null:
		_pc_combatant = handoff.pc
		_companions.assign(handoff.companions)
		_bench.assign(handoff.bench)
		_shop_stock = handoff.shop_stock
		_party_inventory = handoff.party_inventory
		_vault = handoff.vault
		handoff.clear_party()
	else:
		var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
		_pc_combatant = party_seed["pc"]
		_companions.assign(party_seed["companions"])
		_bench.assign(party_seed["bench"])
		_party_inventory = party_seed["party_inventory"]
		_vault = party_seed["vault"]

func _place_dungeon_enemies() -> void:
	for i in range(FLOOR_ENEMY_IDS.size()):
		var bounds: Rect2 = floor_bounds(i)
		_place_dungeon_enemy("DungeonFloor%dEnemy" % (i + 1), [FLOOR_ENEMY_IDS[i]], bounds.position + ENEMY_LOCAL, i)

func _place_dungeon_enemy(node_name: StringName, enemy_ids: Array[StringName], position: Vector2, floor_index: int) -> void:
	if _handoff().is_defeated(node_name):
		return
	var enemy := OverworldEnemy.new()
	enemy.name = node_name
	enemy.enemy_ids = enemy_ids
	enemy.global_position = position
	enemy.fade_overlay = _fade_overlay
	enemy.pc_combatant = _pc_combatant
	enemy.companions = _companions
	enemy.bench = _bench
	enemy.shop_stock = _shop_stock
	enemy.party_inventory = _party_inventory
	enemy.vault = _vault
	enemy.return_scene_path = "res://world/dungeon_demo.tscn"
	enemy.pc_node = _pc
	enemy.dungeon_floor = floor_index
	_floors[floor_index].add_child(enemy)

func _place_dungeon_key() -> void:
	if _handoff().is_defeated(&"DungeonKeyPickup"):
		return
	var pickup := GroundItemPickup.new()
	pickup.name = "DungeonKeyPickup"
	var key := QuestItem.new()
	key.item_id = &"dungeon_key"
	key.display_name = "Rusty Key"
	pickup.item = key
	pickup.party_inventory = _party_inventory
	pickup.global_position = floor_bounds(1).position + KEY_LOCAL
	pickup.item_picked_up.connect(_on_key_picked_up)
	_floors[1].add_child(pickup)

## Separate from _on_item_picked_up() (which handles transient discard/loot-drop pickups that never
## need "already collected" tracking) — the key is a fixed, deterministic placement, so it needs the
## same mark_defeated()-based persistence RewardPickup/GatheringNode already use.
func _on_key_picked_up(item_name: String) -> void:
	_handoff().mark_defeated(&"DungeonKeyPickup")
	_pickup_debug_label.text = "Picked up: %s" % item_name
	_handoff().log_event("Picked up: %s" % item_name, &"loot")

func _on_item_discarded(item: Resource, _quantity: int) -> void:
	var pickup := GroundItemPickup.new()
	pickup.item = item
	pickup.party_inventory = _party_inventory
	pickup.global_position = _pc.global_position + Vector2(0, 16)
	pickup.item_picked_up.connect(_on_item_picked_up)
	pickup.pickup_rejected.connect(_on_pickup_rejected)
	_pc.get_parent().add_child(pickup)

func _on_item_picked_up(item_name: String) -> void:
	_pickup_debug_label.text = "Picked up: %s" % item_name
	_handoff().log_event("Picked up: %s" % item_name, &"loot")

func _on_pickup_rejected(item_name: String) -> void:
	_pickup_debug_label.text = "Bag full — can't pick up: %s" % item_name

func _process(_delta: float) -> void:
	if _inventory_panel.visible:
		_interact_prompt.hide_prompt()
		_set_highlighted_target(null)
		return
	if not _auto_trigger_armed and _pc.global_position.distance_to(_spawn_position) > AUTO_TRIGGER_ARM_DISTANCE:
		_auto_trigger_armed = true
	var target: Interactable = _pc.nearest_interactable()
	if target != null and target.auto_trigger:
		if not _auto_trigger_armed:
			_interact_prompt.hide_prompt()
			_set_highlighted_target(null)
			return
		target.interact()
		_interact_prompt.hide_prompt()
		_set_highlighted_target(null)
		return
	if target != null:
		_interact_prompt.show_prompt(target.prompt_text)
	else:
		_interact_prompt.hide_prompt()
	_set_highlighted_target(target)

func _set_highlighted_target(target: Interactable) -> void:
	if target == _highlighted_target:
		return
	if _highlighted_target != null:
		_highlighted_target.set_highlighted(false)
	if target != null:
		target.set_highlighted(true)
	_highlighted_target = target

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_event_log"):
		_event_log_panel.visible = not _event_log_panel.visible
		return
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		return
	if _inventory_panel.visible:
		return
	if not event.is_action_pressed("interact"):
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null and not target.auto_trigger:
		target.interact()

func _toggle_inventory() -> void:
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, false)
		_pc.set_movement_paused(true)

func _toggle_stats() -> void:
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, false, &"stats")
		_pc.set_movement_paused(true)
