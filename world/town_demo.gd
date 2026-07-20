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
var _vendor_prompt_panel: VendorPromptPanel
var _shop_panel: ShopPanel
var _pickup_debug_label: Label
var _amber_label: Label
var _quest_tracker: QuestTrackerPanel
var _pc_combatant: Combatant
var _companions: Array[Combatant] = []
var _bench: Array[Combatant] = []
var _party_inventory: PartyInventory
var _vault: Vault
var _shop_stock: Array = []
var _town_exit: SceneExit
var _party_selection_panel: PartySelectionPanel
var _event_log_panel: EventLogPanel

## Fetches the CombatHandoff autoload by path — see overworld_demo.gd's _handoff() for the
## identical rationale (bare `CombatHandoff` identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")

func _ready() -> void:
	_build_exterior()
	_build_interior()
	_build_pc()
	_build_camera()
	_build_ui()
	_wire_doors()
	_build_inventory_demo()
	# TownExit was built in _wire_doors(), before the party existed — wire its party fields now
	# (2026-07-12 shared-party-state work) so leaving town carries the SAME party the overworld
	# will pick back up, instead of each scene seeding its own independent placeholder party.
	_town_exit.pc_combatant = _pc_combatant
	_town_exit.companions = _companions
	_town_exit.bench = _bench
	_town_exit.party_inventory = _party_inventory
	_town_exit.vault = _vault
	_town_exit.shop_stock = _shop_stock
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
	shopkeeper.is_vendor = true
	shopkeeper.dialogue = _make_dialogue("Welcome to the general store! Take a look at what I've got.", "Shopkeeper")
	shopkeeper.vendor_interacted.connect(_on_vendor_interacted.bind(shopkeeper))
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

	# Top-left pickup confirmation/rejection (final-review fix, 2026-07-14-ground-item-pickups
	# design) — mirrors overworld_demo.gd's identical label exactly, so a manually-discarded item
	# picked back up in town gets the same "Picked up: X" / "Bag full" feedback the overworld's
	# RewardPickup already has.
	_pickup_debug_label = Label.new()
	_pickup_debug_label.name = "PickupDebugLabel"
	_pickup_debug_label.position = Vector2(16, 70)
	_pickup_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	_ui_layer.add_child(_pickup_debug_label)

	# Playtest-found gap (2026-07-18): Amber only ever showed on the InventoryMenuPanel's Stats
	# tab, which the player didn't notice — a persistent, always-visible readout is more legible
	# (CLAUDE.md §3 pillar) than a value hidden behind a panel toggle. Refreshed every _process()
	# tick (below) rather than wired to every possible Amber-changing event (shop purchases,
	# combat rewards, etc.) — simplest correct option for a value that changes rarely.
	_amber_label = Label.new()
	_amber_label.name = "AmberLabel"
	_amber_label.position = Vector2(16, 100)
	_amber_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	_ui_layer.add_child(_amber_label)

	_quest_tracker = QuestTrackerPanel.new()
	_quest_tracker.position = Vector2(16, 140)
	_ui_layer.add_child(_quest_tracker)

	_dialogue_box = DialogueBox.new()
	_dialogue_box.position = Vector2(20, 700)
	_dialogue_box.custom_minimum_size = Vector2(600, 100)
	_dialogue_box.closed.connect(_on_dialogue_closed)
	_ui_layer.add_child(_dialogue_box)

	_board_panel = AdventuringBoardPanel.new()
	_board_panel.position = Vector2(500, 150)
	_board_panel.party_selection_pressed.connect(_on_party_selection_pressed)
	_board_panel.entry_selected.connect(_on_board_entry_selected)
	_ui_layer.add_child(_board_panel)
	_board_panel.close()

	_party_selection_panel = PartySelectionPanel.new()
	_party_selection_panel.position = Vector2(500, 150)
	_party_selection_panel.add_companion_requested.connect(_on_add_companion_requested)
	_party_selection_panel.remove_companion_requested.connect(_on_remove_companion_requested)
	_ui_layer.add_child(_party_selection_panel)
	_party_selection_panel.close()

	# Cross-scene event log (2026-07-13-overworld-event-log-design.md) — same widget/wiring as
	# overworld_demo.gd's own EventLogPanel; town needs it too since companion recruit/bench events
	# only happen here.
	_event_log_panel = EventLogPanel.new()
	_event_log_panel.position = Vector2(880, 500)
	_event_log_panel.visible = false
	_ui_layer.add_child(_event_log_panel)
	_event_log_panel.build()
	_event_log_panel.refresh(_handoff().event_log_entries)
	_handoff().event_logged.connect(_event_log_panel.append_line)

## Reuses the shared party carried by CombatHandoff (from a SceneExit transition or a combat
## return trip) if one exists, instead of always seeding a fresh independent placeholder party —
## 2026-07-12 shared-party-state work, closes the town/overworld split noted in
## overworld_demo.gd's own _build_inventory_demo() comment. Mirrors that method's handoff-check
## exactly.
func _build_inventory_demo() -> void:
	var handoff: Node = _handoff()
	if handoff.pc != null:
		_pc_combatant = handoff.pc
		_companions.assign(handoff.companions)
		_bench.assign(handoff.bench)
		_party_inventory = handoff.party_inventory
		_vault = handoff.vault
		_shop_stock = handoff.shop_stock if not handoff.shop_stock.is_empty() else ShopLibrary.general_store()
		handoff.clear_party()
	else:
		var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
		_pc_combatant = party_seed["pc"]
		_companions.assign(party_seed["companions"])
		_bench.assign(party_seed["bench"])
		_party_inventory = party_seed["party_inventory"]
		_vault = party_seed["vault"]
		_shop_stock = ShopLibrary.general_store()

	_inventory_panel = InventoryMenuPanel.new()
	_inventory_panel.position = Vector2(140, 60)
	_inventory_panel.hide()
	_ui_layer.add_child(_inventory_panel)
	_inventory_panel.item_discarded.connect(_on_item_discarded)
	_inventory_panel.thank_you_note_requested.connect(_dialogue_box.open)

	_vendor_prompt_panel = VendorPromptPanel.new()
	_vendor_prompt_panel.hide()
	_ui_layer.add_child(_vendor_prompt_panel)
	_vendor_prompt_panel.talk_pressed.connect(_on_vendor_talk_pressed)
	_vendor_prompt_panel.shop_pressed.connect(_on_vendor_shop_pressed)
	_vendor_prompt_panel.leave_pressed.connect(_on_vendor_leave_pressed)

	_shop_panel = ShopPanel.new()
	_shop_panel.hide()
	_ui_layer.add_child(_shop_panel)

## Manual Discard (2026-07-14-ground-item-pickups-design.md §3.7): drop the item at the PC's
## current position. _quantity isn't needed here — [param item] already carries its own
## post-discard quantity (InventoryMenuPanel built a fresh duplicate sized to exactly what left the
## Bag).
func _on_item_discarded(item: Resource, _quantity: int) -> void:
	var pickup := GroundItemPickup.new()
	pickup.item = item
	pickup.party_inventory = _party_inventory
	pickup.global_position = _pc.global_position + Vector2(0, 16)
	pickup.item_picked_up.connect(_on_item_picked_up)
	pickup.pickup_rejected.connect(_on_pickup_rejected)
	_pc.get_parent().add_child(pickup)

## Shown top-left whenever a GroundItemPickup is collected — mirrors overworld_demo.gd's
## _on_item_picked_up (town has no RewardPickup, so this is the first user of the label here).
func _on_item_picked_up(item_name: String) -> void:
	_pickup_debug_label.text = "Picked up: %s" % item_name

## Final-review fix (2026-07-14-ground-item-pickups final review): a full Bag used to reject a
## ground pickup with ZERO player feedback. Mirrors overworld_demo.gd's identical handler.
func _on_pickup_rejected(item_name: String) -> void:
	_pickup_debug_label.text = "Bag full — can't pick up: %s" % item_name

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
	_town_exit = town_exit

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
	var lost_cat_body: String
	var lost_cat_category: QuestBoardEntry.Category
	# _party_inventory is still null the very first time this runs, from _build_exterior() during
	# _ready() (before _build_inventory_demo() has set it) — guard so that first call falls through
	# to the default not-yet-accepted state instead of erroring. Harmless: that initial result is
	# never actually shown to the player (_on_board_opened() always recomputes fresh; see its own
	# comment), it only seeds AdventuringBoard's own now-unused `entries` field.
	if _party_inventory != null and _party_inventory.has_completed_quest(&"lost_cat"):
		lost_cat_body = "Whiskers is home safe, thanks to you."
		lost_cat_category = QuestBoardEntry.Category.RECAP
	elif _party_inventory != null and _party_inventory.has_accepted_quest(&"lost_cat"):
		lost_cat_body = "Bring the rescued cat back here to complete the quest."
		lost_cat_category = QuestBoardEntry.Category.CURRENT
	else:
		lost_cat_body = "A cat's gone missing — last seen near the old dungeon entrance. Whoever finds it should bring it back here."
		lost_cat_category = QuestBoardEntry.Category.SIDE
	var raw: Array[Dictionary] = [
		{"title": "Clear the Cellar", "category": QuestBoardEntry.Category.CURRENT, "body": "Coming soon.", "id": &""},
		{"title": "Lost Cat", "category": lost_cat_category, "body": lost_cat_body, "id": &"lost_cat"},
		{"title": "How We Got Here", "category": QuestBoardEntry.Category.RECAP, "body": "Coming soon.", "id": &""},
	]
	var entries: Array[QuestBoardEntry] = []
	for data in raw:
		var entry := QuestBoardEntry.new()
		entry.title = data["title"]
		entry.category = data["category"]
		entry.body_text = data["body"]
		entry.id = data["id"]
		entries.append(entry)
	return entries

## Also pauses the talking Villager's own wandering — otherwise it can keep moving (and,
## via move_and_slide()'s push-out, drag the PC along with it) for the whole conversation.
func _on_dialogue_requested(dialogue_set: DialogueSet, villager: Villager) -> void:
	_talking_to = villager
	villager.set_wander_paused(true)
	_pc.set_movement_paused(true)
	_dialogue_box.open(dialogue_set)

func _on_dialogue_closed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_pc.set_movement_paused(false)

## WoW-style vendor front door (2026-07-17 general store design §3.6): the Shopkeeper's interact
## opens a Talk/Shop/Leave prompt instead of jumping straight into dialogue.
func _on_vendor_interacted(dialogue_set: DialogueSet, villager: Villager) -> void:
	_talking_to = villager
	villager.set_wander_paused(true)
	_pc.set_movement_paused(true)
	_vendor_prompt_panel.open_for(dialogue_set)

func _on_vendor_talk_pressed() -> void:
	# Talk hands off to the existing linear DialogueBox flow unchanged — _on_dialogue_closed()
	# (already wired to DialogueBox.closed) resumes movement/wander when it finishes.
	_dialogue_box.open(_talking_to.dialogue)

func _on_vendor_shop_pressed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_shop_panel.open_for(_party_inventory, _shop_stock)

func _on_vendor_leave_pressed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_pc.set_movement_paused(false)

## The [param entries] argument is AdventuringBoard's own frozen `entries` field (set once, at scene
## construction, before _party_inventory exists) — it's ignored here and recomputed fresh instead.
## Using it directly would re-show stale quest state on every reopen: _on_board_entry_selected()
## already refreshes the currently-OPEN panel after accept/turn-in, but a subsequent close+reopen
## would otherwise revert to whatever _make_quest_entries() returned back at _build_exterior() time
## (2026-07-19-lost-cat-quest-system-design.md §3.3 board-interactivity work).
func _on_board_opened(_entries: Array[QuestBoardEntry]) -> void:
	_board_panel.open_for(_make_quest_entries())
	_pc.set_movement_paused(true)

## Party Selection (2026-07-12, player-requested): the board hands off to a separate panel rather
## than growing its own quest-row UI to also manage the party. Closes the board panel first so only
## one modal panel is ever open at a time (mirrors _toggle_inventory's existing dialogue/board guard).
func _on_party_selection_pressed() -> void:
	_board_panel.close()
	_party_selection_panel.open_for(_pc_combatant, _companions, _bench)

func _on_add_companion_requested(companion: Combatant) -> void:
	if PartySelectionPanel.party_full(_companions):
		return
	_companions.append(companion)
	_bench.erase(companion)
	_handoff().log_event("Recruited %s to the party" % companion.display_name, &"party")
	_party_selection_panel.open_for(_pc_combatant, _companions, _bench)

func _on_remove_companion_requested(companion: Combatant) -> void:
	_companions.erase(companion)
	_bench.append(companion)
	_handoff().log_event("Benched %s" % companion.display_name, &"party")
	_party_selection_panel.open_for(_pc_combatant, _companions, _bench)

## Lost Cat quest board interactivity (2026-07-19-lost-cat-quest-system-design.md §3.3): a placeholder
## row (empty id) always no-ops; an unaccepted row accepts on click and re-renders; an
## accepted-but-not-ready row no-ops; a completed row no-ops; the Lost Cat row specifically turns in
## (consumes rescued_cat, completes the quest, grants the Thank You Note) once the party holds the
## rescued cat.
func _on_board_entry_selected(entry: QuestBoardEntry) -> void:
	if entry.id == &"":
		return
	if not _party_inventory.has_accepted_quest(entry.id):
		_party_inventory.accept_quest(entry.id)
		_board_panel.open_for(_make_quest_entries())
		return
	if _party_inventory.has_completed_quest(entry.id):
		return
	if entry.id == &"lost_cat" and _party_inventory.has_quest_item(&"rescued_cat"):
		_party_inventory.consume_quest_item(&"rescued_cat")
		_party_inventory.complete_quest(&"lost_cat")
		_party_inventory.give_quest_item(_make_thank_you_note())
		_board_panel.open_for(_make_quest_entries())

## The Lost Cat quest's turn-in reward (2026-07-19-lost-cat-quest-system-design.md) — a QuestItem so
## it shows in the Quest Items tab like the dungeon's Rusty Key.
func _make_thank_you_note() -> QuestItem:
	var note := QuestItem.new()
	note.item_id = &"thank_you_note"
	note.display_name = "A Thank You Note"
	return note

func _process(_delta: float) -> void:
	_amber_label.text = "Amber: %d" % _party_inventory.amber
	_quest_tracker.refresh(_party_inventory)
	if _dialogue_box.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open():
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
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open():
		return
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, true)   # town = safe zone, Vault reachable
		_pc.set_movement_paused(true)

## Opens the same InventoryMenuPanel directly to its Stats tab (2026-07-12, player-requested
## WoW-style 'C' character-pane keybinding) — same toggle semantics as _toggle_inventory(), just a
## different starting tab.
func _toggle_stats() -> void:
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open():
		return
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, true, &"stats")
		_pc.set_movement_paused(true)

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
	if _dialogue_box.is_open():
		_dialogue_box.advance()
		return
	if _board_panel.is_open():
		_board_panel.close()
		_pc.set_movement_paused(false)
		return
	if _party_selection_panel.is_open():
		_party_selection_panel.close()
		_pc.set_movement_paused(false)
		return
	if _vendor_prompt_panel.is_open():
		_vendor_prompt_panel.close()
		if _talking_to != null:
			_talking_to.set_wander_paused(false)
			_talking_to = null
		_pc.set_movement_paused(false)
		return
	if _shop_panel.is_open():
		_shop_panel.close()
		_pc.set_movement_paused(false)
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		target.interact()
