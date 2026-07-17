class_name OverworldEnemy
extends CharacterBody2D

## A hostile wandering NPC representing an overworld encounter (Chrono Trigger/Paper Mario
## TTYD-style — touching it triggers combat). Mirrors world/villager.gd's wander shape but is
## contact-triggered instead of Talk-prompted: its composed Interactable has auto_trigger = true
## and a small (contact-sized) interaction_radius, so the driving scene's per-frame interaction
## poll fires it immediately on proximity rather than waiting for a keypress.
## See docs/superpowers/specs/2026-07-11-overworld-npc-encounters-design.md §3.3.

## Fixed enemy roster for this placement (EnemyLibrary ids, e.g. [&"rat"]). Just data carried on
## the node — nothing here looks these up in EnemyLibrary.
@export var enemy_ids: Array[StringName] = []

@export var wander_leash_radius: float = 48.0
@export var wander_speed: float = 40.0
@export var wander_pause_seconds: float = 1.5

## The scene's FadeOverlay — interact() awaits its fade_out() before swapping scenes (mirrors
## SceneExit.fade_overlay).
@export var fade_overlay: FadeOverlay

## Placement-time fields (set externally by the driving scene, same convention as
## Door.pc/RewardPickup.party_inventory) — the real overworld party fighting this encounter.
var pc_combatant: Combatant
var companions: Array = []
## Precreated companions available to recruit but not currently in the active party (2026-07-12
## Party Selection work) — carried through so a combat round-trip doesn't silently wipe it (see
## CombatHandoff.bench's own playtest-found-bug note).
var bench: Array = []
## The town's live shop-stock array (2026-07-17 general store design) — carried through this
## encounter's handoff exactly like bench/party_inventory/vault, even though combat itself never
## reads it (mirrors bench's own "carried through without inspection" precedent, and closes the
## exact gap CombatHandoff.bench's playtest-found-bug note warns about: a new field only tested via
## stash_party()/SceneExit missing the real bug in begin_encounter()/OverworldEnemy).
var shop_stock: Array = []
var party_inventory: PartyInventory
var vault: Vault
## Which dungeon floor this placement lives on (2026-07-17 dungeon-scene-structure design).
## Irrelevant (stays 0) for overworld placements — only dungeon_demo.gd's _place_dungeon_enemy() sets
## this to a non-zero value.
var dungeon_floor: int = 0
var return_scene_path: String = ""
## The actual PC scene node (not this enemy's own position) — read at trigger time so
## CombatHandoff.return_position reflects where the PC was standing, not where the enemy was.
var pc_node: Node2D

var _home_position: Vector2
var _wander_target: Vector2
var _pause_timer: float = 0.0
## One-shot guard (playtest-found bug, 2026-07-13): unlike RewardPickup/GatheringNode/
## RandomEncounterNode — which all queue_free() themselves inside interact(), making them
## naturally single-shot — this enemy stays alive and in-range through the multi-frame
## `await fade_overlay.fade_out()` below (FadeOverlay.FADE_DURATION = 0.3s, ~18-23 frames).
## Without this guard, overworld_demo.gd's _process() re-fires interact() -> _on_interacted()
## every one of those frames, which used to be harmless (begin_encounter() just overwrites the
## same fields) but became visibly broken the moment _begin_handoff() started also calling
## log_event() — 23 "Encounter started" lines for one trigger.
var _triggered: bool = false

func _ready() -> void:
	_home_position = global_position
	_wander_target = global_position

	var body_shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 8.0
	capsule.height = 20.0
	body_shape.shape = capsule
	add_child(body_shape)

	var visual := ColorRect.new()
	visual.color = Color(0.7, 0.2, 0.2)
	visual.position = Vector2(-8, -12)
	visual.size = Vector2(16, 24)
	add_child(visual)

	var interaction_zone := Interactable.new()
	interaction_zone.name = "InteractionZone"
	interaction_zone.prompt_text = "Fight"
	interaction_zone.auto_trigger = true
	interaction_zone.interaction_radius = 10.0
	add_child(interaction_zone)
	interaction_zone.interacted.connect(_on_interacted)

func _physics_process(delta: float) -> void:
	if global_position.distance_to(_wander_target) < 2.0:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_wander_target = Wander.random_target(_home_position, wander_leash_radius, randf_range(0.0, TAU), randf())
			_pause_timer = wander_pause_seconds
		return
	var direction: Vector2 = global_position.direction_to(_wander_target)
	velocity = direction * wander_speed
	move_and_slide()

func _on_interacted() -> void:
	if _triggered:
		return
	_triggered = true
	_begin_handoff()
	await fade_overlay.fade_out()
	get_tree().change_scene_to_file("res://combat/combat.tscn")

## Populates CombatHandoff with this encounter's party/enemy data. Split out from
## _on_interacted() so tests can drive exactly the CombatHandoff-population effect without
## triggering the fade + change_scene_to_file (which would try to swap the test runner's own
## scene mid-test).
func _begin_handoff() -> void:
	var enemy_names: Array[String] = []
	for id: StringName in enemy_ids:
		enemy_names.append(EnemyLibrary.label(id))
	_handoff().log_event("Encounter started: %s" % ", ".join(enemy_names), &"combat")
	_handoff().begin_encounter(pc_combatant, companions, party_inventory, vault, enemy_ids,
		StringName(name), return_scene_path, pc_node.global_position, bench, shop_stock, dungeon_floor)

## Fetches the CombatHandoff autoload by path rather than referencing it as a bare global
## identifier. Referencing the bare `CombatHandoff` identifier compiles fine when the editor/
## exported game runs a scene normally, but fails to resolve ("Identifier not found") when this
## script is compiled as a dependency under `--headless --script <test>.gd` (confirmed empirically
## — see the identical fix + rationale in combat/combat.gd's own `_handoff()`) — the autoload NODE
## still exists at /root/CombatHandoff either way, so this lookup works in both contexts.
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
