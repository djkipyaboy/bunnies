class_name OverworldDemo
extends Node2D

## Root scene for the overworld demo prototype (2026-07-08-overworld-demo-prototype-design.md).
## Flat top-down, same style/camera/movement code as town_demo.gd — the design bible's locked
## tilted/dimetric overworld look is a separate, later visual pass (spec §0). Proves: a
## walkable map with real physical obstacles (a river only crossable at one bridge), and a
## landmark that transitions to a DIFFERENT scene (town_demo.tscn) via a fade, unlike the
## town's same-scene, no-fade Door toggle. No content commitment: layout/obstacle positions
## are disposable placeholders.

const OVERWORLD_BOUNDS := Rect2(0, 0, 1280, 720)
const RIVER_X_START: float = 600.0
const RIVER_WIDTH: float = 60.0
const BRIDGE_GAP_Y_START: float = 300.0
const BRIDGE_GAP_HEIGHT: float = 80.0
const MOUNTAIN_RECT := Rect2(1080, 40, 160, 160)
const VILLAGE_POSITION := Vector2(200, 360)
const PC_SPAWN := Vector2(200, 460)
const GROUND_DROP_SCATTER_RADIUS: float = 24.0   # [ASSUMPTION] small fixed ring around the return spot

## Playtest-found softlock (2026-07-17, dungeon-scene-structure-design.md work — the identical latent
## bug also applies here): losing a fight returns the PC to return_position — right where the
## still-alive enemy is, since a loss never marks it defeated — and the respawned enemy's auto_trigger
## zone can overlap the PC's spawn point on the very first processed frame, immediately re-firing the
## SAME encounter before the player can move. Requiring genuine movement away from the spawn point
## before any auto_trigger interactable can fire closes this without needing to know win/loss at all —
## a fresh scene load already spawns far from every placed enemy, so this is a no-op there.
const AUTO_TRIGGER_ARM_DISTANCE: float = 40.0

var _world: Node2D
var _pc: PCController
var _camera: Camera2D
var _interact_prompt: InteractPrompt
var _fade_overlay: FadeOverlay
var _highlighted_target: Interactable
var _dialogue_box: DialogueBox
var _talking_to: Villager
var _pickup_debug_label: Label
var _amber_label: Label
var _location_label: Label
var _quest_tracker: QuestTrackerPanel
var _jackpot_bar: ProgressBar
var _jackpot_caption: Label
var _random_encounter_panel: RandomEncounterPanel
var _foraging_panel: ForagingPanel
var _fishing_panel: FishingPanel
var _event_log_panel: EventLogPanel

var _pc_combatant: Combatant
var _companions: Array = []
var _bench: Array = []
var _shop_stock: Array = []
var _party_inventory: PartyInventory
var _vault: Vault
var _inventory_panel: InventoryMenuPanel
var _talent_panel: TalentMenuPanel
var _village_entrance: SceneExit
var _dungeon_entrance: SceneExit
var _spawn_position: Vector2 = Vector2.ZERO
var _auto_trigger_armed: bool = false

## Fetches the CombatHandoff autoload by path rather than referencing it as a bare global
## identifier. Referencing the bare `CombatHandoff` identifier compiles fine when the editor/
## exported game runs a scene normally, but fails to resolve ("Identifier not found") when this
## script is compiled as a dependency under `--headless --script <test>.gd` (confirmed
## empirically — see the identical fix + rationale in combat/combat.gd's own `_handoff()`) — the
## autoload NODE still exists at /root/CombatHandoff either way, so this lookup works in both
## contexts.
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")

func _ready() -> void:
	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)
	_build_world()
	_build_pc()
	_build_camera()
	_build_ui()
	_build_inventory_demo()
	# VillageEntrance was built in _build_world(), before the party existed — wire its party
	# fields now (2026-07-12 shared-party-state work) so entering town carries the SAME party
	# town_demo.tscn will pick back up.
	_village_entrance.pc_combatant = _pc_combatant
	_village_entrance.companions = _companions
	_village_entrance.bench = _bench
	_village_entrance.party_inventory = _party_inventory
	_village_entrance.vault = _vault
	_village_entrance.shop_stock = _shop_stock
	# DungeonEntranceDebug was built in _build_world() (via _build_mountain()), before the party
	# existed — wire its party fields now too, mirroring VillageEntrance immediately above, so
	# walking into the dungeon carries the SAME live party.
	_dungeon_entrance.pc_combatant = _pc_combatant
	_dungeon_entrance.companions = _companions
	_dungeon_entrance.bench = _bench
	_dungeon_entrance.party_inventory = _party_inventory
	_dungeon_entrance.vault = _vault
	_dungeon_entrance.shop_stock = _shop_stock
	_build_npcs()
	_spawn_ground_drops()

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)

	var ground := ColorRect.new()
	ground.color = Color(0.5, 0.6, 0.4)
	ground.position = OVERWORLD_BOUNDS.position
	ground.size = OVERWORLD_BOUNDS.size
	_world.add_child(ground)

	_build_river()
	_build_mountain()
	_build_trees()
	_build_village()

	WorldGeometry.add_boundary_walls(_world, OVERWORLD_BOUNDS)

func _build_river() -> void:
	var river_visual := ColorRect.new()
	river_visual.color = Color(0.3, 0.5, 0.75)
	river_visual.position = Vector2(RIVER_X_START, OVERWORLD_BOUNDS.position.y)
	river_visual.size = Vector2(RIVER_WIDTH, OVERWORLD_BOUNDS.size.y)
	_world.add_child(river_visual)

	var bridge_gap_end: float = BRIDGE_GAP_Y_START + BRIDGE_GAP_HEIGHT
	var river_north := Rect2(RIVER_X_START, OVERWORLD_BOUNDS.position.y, RIVER_WIDTH, BRIDGE_GAP_Y_START - OVERWORLD_BOUNDS.position.y)
	var river_south := Rect2(RIVER_X_START, bridge_gap_end, RIVER_WIDTH, OVERWORLD_BOUNDS.end.y - bridge_gap_end)
	WorldGeometry.add_solid_collider(_world, river_north)
	WorldGeometry.add_solid_collider(_world, river_south)

	var bridge_deck := ColorRect.new()
	bridge_deck.color = Color(0.55, 0.4, 0.25)
	bridge_deck.position = Vector2(RIVER_X_START - 10.0, BRIDGE_GAP_Y_START)
	bridge_deck.size = Vector2(RIVER_WIDTH + 20.0, BRIDGE_GAP_HEIGHT)
	_world.add_child(bridge_deck)

func _build_mountain() -> void:
	var visual := ColorRect.new()
	visual.color = Color(0.5, 0.5, 0.52)
	visual.position = MOUNTAIN_RECT.position
	visual.size = MOUNTAIN_RECT.size
	_world.add_child(visual)
	WorldGeometry.add_solid_collider(_world, MOUNTAIN_RECT)

	var dungeon_entrance := SceneExit.new()
	dungeon_entrance.name = "DungeonEntranceDebug"
	dungeon_entrance.prompt_text = "Enter the Dungeon"
	dungeon_entrance.target_scene_path = "res://world/dungeon_demo.tscn"
	dungeon_entrance.global_position = MOUNTAIN_RECT.position + Vector2(MOUNTAIN_RECT.size.x / 2.0, MOUNTAIN_RECT.size.y + 20.0)
	dungeon_entrance.fade_overlay = _fade_overlay
	_world.add_child(dungeon_entrance)
	_dungeon_entrance = dungeon_entrance

	# Same yellow scene-exit arrow convention as town_demo.gd's TownExit/ExitDoor (playtest-found
	# UX gap, 2026-07-17 — the entrance sat on flat ground next to the mountain with no visual
	# indicator at all).
	var arrow := Polygon2D.new()
	arrow.name = "DungeonEntranceArrow"
	arrow.color = Color(1.0, 0.95, 0.4)
	arrow.modulate.a = Interactable.DIM_ALPHA
	arrow.polygon = PackedVector2Array([
		Vector2(-4, -15), Vector2(4, -15), Vector2(4, 5),
		Vector2(10, 5), Vector2(0, 20), Vector2(-10, 5), Vector2(-4, 5),
	])
	dungeon_entrance.add_child(arrow)
	dungeon_entrance.highlight_visual = arrow

func _build_trees() -> void:
	var tree_positions: Array[Vector2] = [
		Vector2(80, 150), Vector2(350, 120), Vector2(450, 550), Vector2(120, 600),
		Vector2(750, 180), Vector2(950, 500), Vector2(1150, 300),
	]
	for tree_position: Vector2 in tree_positions:
		_world.add_child(_build_tree(tree_position))

func _build_tree(tree_position: Vector2) -> Node2D:
	var tree := Node2D.new()
	tree.position = tree_position

	var trunk := ColorRect.new()
	trunk.color = Color(0.4, 0.28, 0.16)
	trunk.position = Vector2(-4, -4)
	trunk.size = Vector2(8, 16)
	tree.add_child(trunk)

	var canopy := ColorRect.new()
	canopy.color = Color(0.25, 0.45, 0.22)
	canopy.position = Vector2(-14, -28)
	canopy.size = Vector2(28, 28)
	tree.add_child(canopy)

	WorldGeometry.add_solid_collider(tree, Rect2(-10, -10, 20, 20))
	return tree

func _build_village() -> void:
	var landmark := Node2D.new()
	landmark.position = VILLAGE_POSITION

	var roof := Polygon2D.new()
	roof.color = Color(0.42, 0.26, 0.18)
	roof.polygon = PackedVector2Array([Vector2(-30, 10), Vector2(0, -30), Vector2(30, 10)])
	landmark.add_child(roof)

	var body := ColorRect.new()
	body.color = Color(0.72, 0.58, 0.38)
	body.position = Vector2(-25, 10)
	body.size = Vector2(50, 30)
	landmark.add_child(body)

	_world.add_child(landmark)
	WorldGeometry.add_solid_collider(_world, Rect2(VILLAGE_POSITION.x - 25.0, VILLAGE_POSITION.y + 10.0, 50.0, 30.0))

	var entrance := SceneExit.new()
	entrance.name = "VillageEntrance"
	entrance.prompt_text = "Enter Village"
	entrance.target_scene_path = "res://world/town_demo.tscn"
	entrance.global_position = VILLAGE_POSITION + Vector2(0, 40)
	entrance.fade_overlay = _fade_overlay
	_world.add_child(entrance)
	_village_entrance = entrance

func _build_pc() -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	var handoff: Node = _handoff()
	# Priority: a real combat round-trip's exact pre-fight spot, then a plain SceneExit's own
	# specified spawn (2026-07-17 playtest-found fix — the dungeon's exit points back at the
	# mountain instead of this generic default), then the generic default.
	if handoff.has_return_position:
		_pc.global_position = handoff.return_position
	elif handoff.has_entry_spawn_position:
		_pc.global_position = handoff.entry_spawn_position
	else:
		_pc.global_position = PC_SPAWN
	_spawn_position = _pc.global_position
	# Consumed — clear it so a LATER return trip (e.g. leaving to town and back) doesn't reuse this
	# stale position (final-review Critical finding, 2026-07-11: combat.gd no longer clears this
	# half of the handoff, so it's this scene's job once it's actually read the value).
	handoff.clear_return_position()
	handoff.clear_entry_spawn_position()

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

	_world.add_child(_pc)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	_camera.limit_left = int(OVERWORLD_BOUNDS.position.x)
	_camera.limit_top = int(OVERWORLD_BOUNDS.position.y)
	_camera.limit_right = int(OVERWORLD_BOUNDS.end.x)
	_camera.limit_bottom = int(OVERWORLD_BOUNDS.end.y)
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

	_talent_panel = TalentMenuPanel.new()
	_talent_panel.position = Vector2(140, 60)
	_talent_panel.hide()
	ui.add_child(_talent_panel)

	_dialogue_box = DialogueBox.new()
	_dialogue_box.position = Vector2(20, 700)
	_dialogue_box.custom_minimum_size = Vector2(600, 100)
	_dialogue_box.closed.connect(_on_dialogue_closed)
	ui.add_child(_dialogue_box)

	_random_encounter_panel = RandomEncounterPanel.new()
	_random_encounter_panel.position = Vector2(140, 60)
	_random_encounter_panel.resolved.connect(_on_random_encounter_resolved)
	ui.add_child(_random_encounter_panel)
	_random_encounter_panel.close()

	_foraging_panel = ForagingPanel.new()
	_foraging_panel.position = Vector2(140, 60)
	_foraging_panel.foraging_completed.connect(_on_foraging_completed)
	ui.add_child(_foraging_panel)

	_fishing_panel = FishingPanel.new()
	_fishing_panel.position = Vector2(140, 60)
	_fishing_panel.fishing_completed.connect(_on_fishing_completed)
	_fishing_panel.fishing_closed.connect(_on_fishing_closed)
	ui.add_child(_fishing_panel)

	# Top-left pickup confirmation (player request 2026-07-11) — same top-left placement/style
	# convention as the encounter message, but yellow and its own line so both can be visible at
	# once without one overwriting the other.
	_pickup_debug_label = Label.new()
	_pickup_debug_label.name = "PickupDebugLabel"
	_pickup_debug_label.position = Vector2(16, 70)
	_pickup_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	ui.add_child(_pickup_debug_label)

	# Playtest-found gap (2026-07-18): Amber only ever showed on the InventoryMenuPanel's Stats
	# tab, which the player didn't notice — a persistent, always-visible readout is more legible
	# than a value hidden behind a panel toggle. Refreshed every _process() tick (below).
	_amber_label = Label.new()
	_amber_label.name = "AmberLabel"
	_amber_label.position = Vector2(16, 100)
	_amber_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	ui.add_child(_amber_label)

	_quest_tracker = QuestTrackerPanel.new()
	_quest_tracker.position = Vector2(16, 140)
	ui.add_child(_quest_tracker)

	# Jackpot Meter HUD (2026-07-29 spec §2): a translucent fill-bar, no raw numbers — mirrors
	# CombatantPanel's Bonus Meter bar convention (ProgressBar, show_percentage=false). A caption
	# label + a lower y-position (final-review fix 2026-07-30) — previously unlabeled and close
	# enough to the quest tracker's 2-line text (up to ~y186 when active) to visually clip it.
	_jackpot_caption = Label.new()
	_jackpot_caption.text = "Jackpot"
	_jackpot_caption.add_theme_font_size_override("font_size", 12)
	_jackpot_caption.position = Vector2(16, 195)
	ui.add_child(_jackpot_caption)

	_jackpot_bar = ProgressBar.new()
	_jackpot_bar.name = "JackpotBar"
	_jackpot_bar.show_percentage = false
	_jackpot_bar.position = Vector2(16, 213)
	_jackpot_bar.custom_minimum_size = Vector2(200, 16)
	_jackpot_bar.modulate = Color(1.0, 0.84, 0.4, 0.6)
	_jackpot_bar.max_value = PartyInventory.JACKPOT_CAP
	ui.add_child(_jackpot_bar)

	# Location indicator (2026-07-23 playtest feedback): a persistent corner label naming where the
	# PC currently is — top-right, clear of the left-side interact/pickup/Amber/quest stack.
	_location_label = Label.new()
	_location_label.name = "LocationLabel"
	_location_label.text = "Overworld"
	_location_label.position = Vector2(1360, 16)
	_location_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	ui.add_child(_location_label)

	# Cross-scene event log (2026-07-13-overworld-event-log-design.md) — non-modal, toggled with
	# toggle_event_log (L), translucent until hovered. Seeded from whatever history already exists
	# (a prior town/combat visit this session) and kept live via CombatHandoff.event_logged.
	_event_log_panel = EventLogPanel.new()
	_event_log_panel.position = Vector2(880, 500)
	_event_log_panel.visible = false
	ui.add_child(_event_log_panel)
	_event_log_panel.build()
	_event_log_panel.refresh(_handoff().event_log_entries)
	_handoff().event_logged.connect(_event_log_panel.append_line)

## The overworld map is not a safe zone — the Vault is passed in but marked unreachable
## (open_for's vault_available=false) so a player can still adjust Bag/equipped gear before an
## overworld encounter without being able to bank.
##
## Reuses the shared party carried by CombatHandoff (town_demo.gd's SceneExit, or a combat return
## trip) if one exists, instead of always reseeding a fresh independent placeholder party — as of
## 2026-07-12 town and overworld share ONE live party rather than two independently-seeded demos
## (closes the seam this comment used to describe). Falls back to InventoryDemoSetup.
## seed_demo_party() only on a genuinely first-ever launch (no prior handoff at all).
##
## History: returning from a fight used to always call seed_demo_party() unconditionally,
## discarding whatever the fought party's live equipment/HP state was (playtest-found gap,
## 2026-07-12) — fixed by checking CombatHandoff.pc first, which this method still does.
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

## Places the three placeholder NPCs the encounters spec calls for (2026-07-11-overworld-npc-
## encounters-design.md §3.6) — one hostile OverworldEnemy, one stationary RewardPickup, one
## friendly dialogue Villager — all children of _world (same Y-sort/collision context as every
## other overworld object). Positions are disposable placeholders chosen clear of the river/
## mountain/tree/village colliders and the PC spawn.
func _build_npcs() -> void:
	# (800, 400) sits in open ground east of the river (river ends at x=660) and well clear of
	# every tree/mountain/village collider by more than the default 48px wander_leash_radius —
	# the previous (500, 550) placement was only ~41px from the (450, 550) tree's collider,
	# close enough that a wander target could land inside it, visibly sticking the rat in place.
	_place_overworld_enemy("OverworldRat", [&"rat"], Vector2(800, 400))
	# More overworld encounter variety (player direction 2026-07-12): ferret/stoat were already
	# authored in EnemyLibrary but never placed. Positions clear of every collider/other NPC above.
	_place_overworld_enemy("OverworldFerret", [&"ferret"], Vector2(1000, 250))
	_place_overworld_enemy("OverworldStoat", [&"stoat"], Vector2(700, 600))

	if not _handoff().is_defeated(&"ShinyTrinket"):
		var reward := RewardPickup.new()
		reward.name = "ShinyTrinket"
		var trinket_gear := Gear.new()
		trinket_gear.display_name = "Shiny Trinket"
		trinket_gear.stat_bonuses = Stats.new()
		reward.reward_gear = trinket_gear
		reward.party_inventory = _party_inventory
		reward.global_position = Vector2(900, 150)
		reward.item_picked_up.connect(_on_item_picked_up)
		_world.add_child(reward)

	var wanderer := Villager.new()
	wanderer.name = "OverworldWanderer"
	wanderer.dialogue = _make_dialogue("Careful out there, traveler.", "Wanderer")
	wanderer.can_wander = true
	wanderer.global_position = Vector2(300, 250)
	wanderer.dialogue_requested.connect(_on_dialogue_requested.bind(wanderer))
	_world.add_child(wanderer)

	# Environmental gathering nodes (design-bible 27-crafting.md §11, player direction 2026-07-12) —
	# basic one-shot interactables for this playtest, no mini-game reel yet. Positions chosen clear
	# of every tree/mountain/village/river collider and the other placed NPCs above.
	if not _handoff().is_defeated(&"WildBerries"):
		var berries := GatheringNode.new()
		berries.name = "WildBerries"
		berries.material_type = &"forage_herb"
		berries.material_display_name = "Wild Berries"
		berries.quantity = 1
		berries.global_position = Vector2(150, 550)
		berries.foraging_requested.connect(_on_foraging_requested)
		_world.add_child(berries)

	if not _handoff().is_defeated(&"FishingSpot"):
		var fish := FishingSpot.new()
		fish.name = "FishingSpot"
		fish.small_material_type = &"fish_small"
		fish.small_material_display_name = "Minnow"
		fish.small_quantity = 1
		fish.medium_material_type = &"fish_medium"
		fish.medium_material_display_name = "Freshwater Fish"
		fish.medium_quantity = 1
		fish.large_material_type = &"fish_large"
		fish.large_material_display_name = "Prize Bass"
		fish.large_quantity = 1
		fish.global_position = Vector2(560, 340)
		fish.fishing_requested.connect(_on_fishing_requested)
		_world.add_child(fish)

	# Slay-the-Spire-style "?" random encounter (player direction 2026-07-12) — one authored
	# example (bandit_ambush) for this playtest. Positioned clear of every collider/other NPC.
	if not _handoff().is_defeated(&"BanditAmbush"):
		var encounter_node := RandomEncounterNode.new()
		encounter_node.name = "BanditAmbush"
		encounter_node.encounter_id = &"bandit_ambush"
		encounter_node.global_position = Vector2(1000, 600)
		encounter_node.encounter_triggered.connect(_on_encounter_triggered)
		_world.add_child(encounter_node)

## Places one OverworldEnemy with the given [param enemy_ids] roster, skipping placement if
## already marked defeated. Factored out (2026-07-12) once ferret/stoat joined the rat as real
## placements — all three wire the identical set of placement-time fields.
func _place_overworld_enemy(node_name: StringName, enemy_ids: Array[StringName], position: Vector2) -> void:
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
	enemy.return_scene_path = "res://world/overworld_demo.tscn"
	enemy.pc_node = _pc
	_world.add_child(enemy)

## Turns any combat-loot overflow left in CombatHandoff into real, collectible GroundItemPickup
## nodes scattered around the PC's current position (2026-07-14-ground-item-pickups-design.md
## §3.5). Must run AFTER _build_pc() (needs _pc.global_position) and AFTER _build_inventory_demo()
## (needs _party_inventory) — called last in _ready().
func _spawn_ground_drops() -> void:
	var handoff: Node = _handoff()
	var drops: Array = handoff.pending_ground_drops
	for i in range(drops.size()):
		var angle: float = float(i) * TAU / maxf(float(drops.size()), 1.0)
		var pos: Vector2 = Wander.random_target(_pc.global_position, GROUND_DROP_SCATTER_RADIUS, angle, 1.0)
		var pickup := GroundItemPickup.new()
		pickup.item = drops[i]
		pickup.party_inventory = _party_inventory
		pickup.global_position = pos
		pickup.item_picked_up.connect(_on_item_picked_up)
		pickup.pickup_rejected.connect(_on_pickup_rejected)
		_world.add_child(pickup)
	handoff.clear_ground_drops()

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

## Also pauses the talking Villager's own wandering — otherwise it can keep moving (and, via
## move_and_slide()'s push-out, drag the PC along with it) for the whole conversation. Mirrors
## town_demo.gd's handler exactly, including the PC-movement-pause fix added there earlier this
## session.
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

## Shown top-left (like the encounter message, but yellow) whenever a RewardPickup or
## GroundItemPickup is collected.
func _on_item_picked_up(item_name: String) -> void:
	_pickup_debug_label.text = "Picked up: %s" % item_name
	_handoff().log_event("Picked up: %s" % item_name, &"loot")

## Final-review fix (2026-07-14-ground-item-pickups final review): a full Bag used to reject a
## ground pickup with ZERO player feedback — the same "silent rejection reads as broken" bug class
## this project has already been bitten by (see the equipment UI's "Requires level N" fix). Reuses
## the same top-left label GroundItemPickup.item_picked_up already writes to.
func _on_pickup_rejected(item_name: String) -> void:
	_pickup_debug_label.text = "Bag full — can't pick up: %s" % item_name

## Opens the Foraging mini-game panel (2026-08-01 gathering-profession-minigames spec section 2) and
## pauses PC movement -- mirrors _on_encounter_triggered's existing pattern.
func _on_foraging_requested(material_type: StringName, material_display_name: String, quantity: int) -> void:
	_foraging_panel.open_for(material_type, material_display_name, quantity, _party_inventory)
	_pc.set_movement_paused(true)

## Banking in the Foraging panel grants the material and closes it -- show the same top-left pickup
## label _on_material_gathered used to, and resume PC movement (mirrors _on_random_encounter_resolved).
func _on_foraging_completed(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Gathered: %s x%d" % [item_name, quantity]
	_handoff().log_event("Gathered: %s x%d" % [item_name, quantity], &"loot")
	_pc.set_movement_paused(false)

## Opens the Fishing mini-game panel (2026-08-01 gathering-profession-minigames spec section 3) and
## pauses PC movement -- mirrors _on_foraging_requested's existing pattern.
func _on_fishing_requested(bucket_configs: Dictionary) -> void:
	_fishing_panel.open_for(bucket_configs, _party_inventory)
	_pc.set_movement_paused(true)

## A completed catch shows the same top-left pickup label the other gathering flows use.
## Resuming movement and writing the event log both now happen via _on_fishing_closed instead
## (2026-08-02 gathering-playtest-fixes spec section 4), since that signal fires on a miss too --
## this one is catch-only.
func _on_fishing_completed(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Caught: %s x%d" % [item_name, quantity]

## Fires unconditionally when the panel closes, catch or miss, carrying the full combined
## per-attempt log line built in FishingPanel._resolve() -- the ONE place that writes the Fishing
## event-log entry and the ONE place guaranteed to resume PC movement.
func _on_fishing_closed(log_line: String) -> void:
	_handoff().log_event(log_line, &"loot")
	_pc.set_movement_paused(false)

## Opens the "?" encounter's choice panel (player direction 2026-07-12) and pauses PC movement —
## mirrors _on_dialogue_requested/_on_board_opened's existing pattern.
func _on_encounter_triggered(encounter: RandomEncounter) -> void:
	_random_encounter_panel.open_for(encounter, _pc_combatant, _party_inventory)
	_pc.set_movement_paused(true)

## The panel already hides itself on Continue (mirrors DialogueBox.closed) — this just resumes
## movement, mirroring _on_dialogue_closed().
func _on_random_encounter_resolved() -> void:
	_pc.set_movement_paused(false)

func _toggle_inventory() -> void:
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible:
		return
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, false)   # overworld = not a safe zone, Vault unreachable
		_pc.set_movement_paused(true)

## Opens the same InventoryMenuPanel directly to its Stats tab (2026-07-12, player-requested
## WoW-style 'C' character-pane keybinding) — same toggle semantics as _toggle_inventory(), just a
## different starting tab.
func _toggle_stats() -> void:
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible:
		return
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, false, &"stats")
		_pc.set_movement_paused(true)

## Talents (Task 23, spec 2026-07-24 §2/§6) — bound to 'N'. Same toggle semantics as
## _toggle_inventory()/_toggle_stats(): pause PC movement while open, resume on close.
func _toggle_talents() -> void:
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _inventory_panel.visible:
		return
	if _talent_panel.visible:
		_talent_panel.close()
		_pc.set_movement_paused(false)
	else:
		_talent_panel.open_for(_pc_combatant, _companions, false)   # overworld = not a safe zone, respec unavailable
		_pc.set_movement_paused(true)

func _process(_delta: float) -> void:
	_amber_label.text = "Amber: %d" % _party_inventory.amber
	_quest_tracker.refresh(_party_inventory)
	_jackpot_bar.value = _party_inventory.jackpot_meter
	if _inventory_panel.visible or _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible:
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
		# Fire immediately on contact instead of showing a prompt for something that's about
		# to disappear this frame (OverworldEnemy/RewardPickup) — the simplest of the two
		# spec-approved options (2026-07-11-overworld-npc-encounters-design.md §3.1/§3.6).
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
	if event.is_action_pressed("toggle_talents"):
		_toggle_talents()
		return
	if _inventory_panel.visible or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible:
		return
	if not event.is_action_pressed("interact"):
		return
	if _dialogue_box.is_open():
		_dialogue_box.advance()
		return
	var target: Interactable = _pc.nearest_interactable()
	# auto_trigger targets are already fired by _process the moment they're in range — don't
	# also fire them here, or a same-frame interact press double-grants a reward/double-emits
	# an encounter (queue_free() is deferred, so the target is still "live" for this frame).
	if target != null and not target.auto_trigger:
		target.interact()
