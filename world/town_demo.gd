class_name TownDemo
extends Node2D

## Root scene for the first-playable-town demo (2026-07-07-demo-town-prototype-design.md).
## Builds the whole plaza + shop interior in code, matching this project's existing
## "build scene content in code, not the editor" convention (combat.gd/AbilityMenuPanel).
## No content commitment: NPC lines, quest rows, and layout are all disposable placeholders.
## What's locked is the movement/interaction/scene-architecture pattern (spec §0).

const EXTERIOR_BOUNDS := Rect2(0, 0, 640, 360)
## Placed well clear of EXTERIOR_BOUNDS (not at the origin) because Door.toggle_areas()
## hides an area with `visible = false` / `PROCESS_MODE_DISABLED` — neither disables physics
## collision in Godot, so a StaticBody2D under a "hidden" area stays solid in world space.
## Overlapping this with EXTERIOR_BOUNDS previously put invisible walls (and a spawned
## Villager) in the middle of the plaza even while the shop interior was "closed".
const INTERIOR_BOUNDS := Rect2(800, 0, 320, 240)
const SHOP_BODY_RECT := Rect2(450, 120, 150, 100)

var _exterior: Node2D
var _interior: Node2D
var _pc: PCController
var _camera: Camera2D
var _dialogue_box: DialogueBox
var _board_panel: AdventuringBoardPanel
var _interact_prompt: InteractPrompt
var _fade_overlay: FadeOverlay
var _shop_entry_marker: Marker2D
var _highlighted_target: Interactable
var _talking_to: Villager
var _ui_layer: CanvasLayer
var _inventory_panel: InventoryMenuPanel
var _pc_combatant: Combatant
var _companions: Array[Combatant] = []
var _party_inventory: PartyInventory
var _vault: Vault

func _ready() -> void:
	_build_exterior()
	_build_interior()
	_build_pc()
	_build_camera()
	_build_ui()
	_wire_doors()
	_build_inventory_demo()
	_interior.visible = false
	_interior.process_mode = Node.PROCESS_MODE_DISABLED

func _build_exterior() -> void:
	_exterior = Node2D.new()
	_exterior.name = "Exterior"
	_exterior.y_sort_enabled = true
	add_child(_exterior)

	var ground := ColorRect.new()
	ground.color = Color(0.55, 0.62, 0.42)
	ground.position = EXTERIOR_BOUNDS.position
	ground.size = EXTERIOR_BOUNDS.size
	_exterior.add_child(ground)

	_exterior.add_child(_build_shop_facade())

	var villager_data: Array[Dictionary] = [
		{"pos": Vector2(100, 250), "line": "Lovely day in the plaza, isn't it?"},
		{"pos": Vector2(300, 300), "line": "Careful near the old well, stranger."},
		{"pos": Vector2(200, 110), "line": "Welcome to town! The shop's got good stock."},
	]
	for i in range(villager_data.size()):
		var villager := Villager.new()
		villager.name = "Villager%d" % i
		villager.global_position = villager_data[i]["pos"]
		villager.dialogue = _make_dialogue(villager_data[i]["line"])
		villager.dialogue_requested.connect(_on_dialogue_requested.bind(villager))
		_exterior.add_child(villager)

	var board := AdventuringBoard.new()
	board.name = "AdventuringBoard"
	board.global_position = Vector2(150, 150)
	board.entries = _make_quest_entries()
	board.board_opened.connect(_on_board_opened)
	_exterior.add_child(board)

	WorldGeometry.add_boundary_walls(_exterior, EXTERIOR_BOUNDS)
	WorldGeometry.add_solid_collider(_exterior, SHOP_BODY_RECT)

func _build_shop_facade() -> Node2D:
	var facade := Node2D.new()
	facade.name = "ShopFacade"
	facade.position = Vector2(450, 80)

	var body := ColorRect.new()
	body.color = Color(0.72, 0.58, 0.38)
	body.position = Vector2(0, 40)
	body.size = Vector2(150, 100)
	facade.add_child(body)

	var roof := Polygon2D.new()
	roof.color = Color(0.42, 0.26, 0.18)
	roof.polygon = PackedVector2Array([Vector2(-10, 40), Vector2(75, -20), Vector2(160, 40)])
	facade.add_child(roof)

	var door_visual := ColorRect.new()
	door_visual.color = Color(0.18, 0.12, 0.08)
	door_visual.position = Vector2(65, 100)
	door_visual.size = Vector2(20, 40)
	facade.add_child(door_visual)

	return facade

func _build_interior() -> void:
	_interior = Node2D.new()
	_interior.name = "ShopInterior"
	_interior.y_sort_enabled = true
	add_child(_interior)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.5, 0.42, 0.32)
	floor_rect.position = INTERIOR_BOUNDS.position
	floor_rect.size = INTERIOR_BOUNDS.size
	_interior.add_child(floor_rect)

	var shopkeeper := Villager.new()
	shopkeeper.name = "Shopkeeper"
	shopkeeper.can_wander = false
	shopkeeper.global_position = Vector2(960, 100)
	shopkeeper.dialogue = _make_dialogue("Welcome! Nothing's actually for sale yet — just testing the shop layout.", "Shopkeeper")
	shopkeeper.dialogue_requested.connect(_on_dialogue_requested.bind(shopkeeper))
	_interior.add_child(shopkeeper)

	_shop_entry_marker = Marker2D.new()
	_shop_entry_marker.name = "EntryMarker"
	_shop_entry_marker.position = Vector2(960, 180)
	_interior.add_child(_shop_entry_marker)

	WorldGeometry.add_boundary_walls(_interior, INTERIOR_BOUNDS)

func _build_pc() -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	_pc.global_position = Vector2(320, 300)

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

	_exterior.add_child(_pc)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	_camera.limit_left = int(EXTERIOR_BOUNDS.position.x)
	_camera.limit_top = int(EXTERIOR_BOUNDS.position.y)
	_camera.limit_right = int(EXTERIOR_BOUNDS.end.x)
	_camera.limit_bottom = int(EXTERIOR_BOUNDS.end.y)
	_pc.add_child(_camera)

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	add_child(_ui_layer)

	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)

	_interact_prompt = InteractPrompt.new()
	_interact_prompt.position = Vector2(16, 16)
	_ui_layer.add_child(_interact_prompt)

	_dialogue_box = DialogueBox.new()
	_dialogue_box.position = Vector2(20, 700)
	_dialogue_box.custom_minimum_size = Vector2(600, 100)
	_dialogue_box.closed.connect(_on_dialogue_closed)
	_ui_layer.add_child(_dialogue_box)

	_board_panel = AdventuringBoardPanel.new()
	_board_panel.position = Vector2(500, 150)
	_ui_layer.add_child(_board_panel)
	_board_panel.close()

func _build_inventory_demo() -> void:
	var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
	_pc_combatant = party_seed["pc"]
	_companions.assign(party_seed["companions"])
	_party_inventory = party_seed["party_inventory"]
	_vault = party_seed["vault"]

	_inventory_panel = InventoryMenuPanel.new()
	_inventory_panel.position = Vector2(140, 60)
	_inventory_panel.hide()
	_ui_layer.add_child(_inventory_panel)

func _wire_doors() -> void:
	# (525, 200) is the drawn door rectangle's center, which sits inside SHOP_BODY_RECT's
	# solid collider. Reachable anyway: PCController's reach radius (24) plus this door's
	# own interaction_radius (16, from Interactable's default) comfortably exceeds the gap
	# between the collider's south face and where the PC's own capsule stops it.
	var shop_door := Door.new()
	shop_door.name = "ShopDoor"
	shop_door.global_position = Vector2(525, 200)
	shop_door.current_area = _exterior
	shop_door.target_area = _interior
	shop_door.entry_marker = _shop_entry_marker
	shop_door.camera = _camera
	shop_door.target_camera_limits = INTERIOR_BOUNDS
	shop_door.pc = _pc
	_exterior.add_child(shop_door)

	var exit_marker := Marker2D.new()
	exit_marker.name = "ShopExitMarker"
	exit_marker.position = Vector2(525, 230)
	_exterior.add_child(exit_marker)

	var exit_door := Door.new()
	exit_door.name = "ExitDoor"
	exit_door.global_position = Vector2(960, 200)
	exit_door.current_area = _interior
	exit_door.target_area = _exterior
	exit_door.entry_marker = exit_marker
	exit_door.camera = _camera
	exit_door.target_camera_limits = EXTERIOR_BOUNDS
	exit_door.pc = _pc
	_interior.add_child(exit_door)

	var exit_arrow := Polygon2D.new()
	exit_arrow.name = "ExitArrow"
	exit_arrow.color = Color(1.0, 0.95, 0.4)
	exit_arrow.modulate.a = Interactable.DIM_ALPHA
	exit_arrow.polygon = PackedVector2Array([
		Vector2(-4, -15), Vector2(4, -15), Vector2(4, 5),
		Vector2(10, 5), Vector2(0, 20), Vector2(-10, 5), Vector2(-4, 5),
	])
	exit_door.add_child(exit_arrow)
	exit_door.highlight_visual = exit_arrow

	var town_exit := SceneExit.new()
	town_exit.name = "TownExit"
	town_exit.prompt_text = "Leave Town"
	town_exit.target_scene_path = "res://world/overworld_demo.tscn"
	town_exit.global_position = Vector2(320, 340)
	town_exit.fade_overlay = _fade_overlay
	_exterior.add_child(town_exit)

	var town_exit_arrow := Polygon2D.new()
	town_exit_arrow.name = "TownExitArrow"
	town_exit_arrow.color = Color(1.0, 0.95, 0.4)
	town_exit_arrow.modulate.a = Interactable.DIM_ALPHA
	town_exit_arrow.polygon = PackedVector2Array([
		Vector2(-4, -15), Vector2(4, -15), Vector2(4, 5),
		Vector2(10, 5), Vector2(0, 20), Vector2(-10, 5), Vector2(-4, 5),
	])
	town_exit.add_child(town_exit_arrow)
	town_exit.highlight_visual = town_exit_arrow

func _make_dialogue(line_text: String, speaker_name: String = "Villager") -> DialogueSet:
	var greeting := DialogueLine.new()
	greeting.speaker_name = speaker_name
	greeting.text = line_text
	var farewell := DialogueLine.new()
	farewell.speaker_name = speaker_name
	farewell.text = "Safe travels!"
	var lines: Array[DialogueLine] = [greeting, farewell]
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = lines
	return dialogue_set

func _make_quest_entries() -> Array[QuestBoardEntry]:
	var raw: Array[Dictionary] = [
		{"title": "Clear the Cellar", "category": QuestBoardEntry.Category.CURRENT, "body": "Coming soon."},
		{"title": "Lost Cat", "category": QuestBoardEntry.Category.SIDE, "body": "Coming soon."},
		{"title": "How We Got Here", "category": QuestBoardEntry.Category.RECAP, "body": "Coming soon."},
	]
	var entries: Array[QuestBoardEntry] = []
	for data in raw:
		var entry := QuestBoardEntry.new()
		entry.title = data["title"]
		entry.category = data["category"]
		entry.body_text = data["body"]
		entries.append(entry)
	return entries

## Also pauses the talking Villager's own wandering — otherwise it can keep moving (and,
## via move_and_slide()'s push-out, drag the PC along with it) for the whole conversation.
func _on_dialogue_requested(dialogue_set: DialogueSet, villager: Villager) -> void:
	_talking_to = villager
	villager.set_wander_paused(true)
	_dialogue_box.open(dialogue_set)

func _on_dialogue_closed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null

func _on_board_opened(entries: Array[QuestBoardEntry]) -> void:
	_board_panel.open_for(entries)

func _process(_delta: float) -> void:
	if _dialogue_box.is_open():
		_interact_prompt.hide_prompt()
		_set_highlighted_target(null)
		return
	var target: Interactable = _pc.nearest_interactable()
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

func _toggle_inventory() -> void:
	if _dialogue_box.is_open() or _board_panel.is_open():
		return
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault)
		_pc.set_movement_paused(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if _inventory_panel.visible:
		return
	if not event.is_action_pressed("interact"):
		return
	if _dialogue_box.is_open():
		_dialogue_box.advance()
		return
	if _board_panel.is_open():
		_board_panel.close()
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		target.interact()
