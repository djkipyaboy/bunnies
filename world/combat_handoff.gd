extends Node

## Minimal persistent bridge for the overworld<->combat.tscn transition (design
## 2026-07-11-overworld-combat-handoff-design.md). Deliberately NOT a general save/game-state
## system — town_demo.gd and overworld_demo.gd keep their own separate placeholder party seeds;
## this only carries the party across an overworld encounter's round trip into combat and back.
##
## Registered as an autoload singleton named "CombatHandoff" in project.godot — this script
## intentionally has NO class_name (autoloads are referenced by their registered name, not a
## class_name).

var pc: Combatant
var companions: Array = []
var party_inventory: PartyInventory
var vault: Vault
var enemy_ids: Array[StringName] = []
var pending_encounter_id: StringName = &""   # the triggering OverworldEnemy's node name
var return_scene_path: String = ""
var return_position: Vector2 = Vector2.ZERO
var has_return_position: bool = false   # ZERO could be a legitimate spawn point; don't sentinel-compare
var defeated_encounter_ids: Array[StringName] = []

func begin_encounter(p: Combatant, comps: Array, inv: PartyInventory, v: Vault,
		ids: Array[StringName], encounter_id: StringName, scene_path: String, position: Vector2) -> void:
	pc = p
	companions = comps
	party_inventory = inv
	vault = v
	enemy_ids = ids
	pending_encounter_id = encounter_id
	return_scene_path = scene_path
	return_position = position
	has_return_position = true

func mark_defeated(encounter_id: StringName) -> void:
	if not defeated_encounter_ids.has(encounter_id):
		defeated_encounter_ids.append(encounter_id)

func is_defeated(encounter_id: StringName) -> bool:
	return defeated_encounter_ids.has(encounter_id)

## Clears the combat-specific data (enemy_ids/pending_encounter_id/return_scene_path) once
## combat.gd has read them, so a later standalone combat.tscn launch doesn't see stale handoff
## data. Deliberately does NOT touch pc/companions/party_inventory/vault or
## return_position/has_return_position — combat.gd calls this BEFORE the scene change, while the
## destination scene (overworld_demo.gd) hasn't had a chance to read any of those yet. Clearing the
## party here would silently discard whatever gear/HP changes happened in the fight before the
## overworld ever got to reuse them (playtest-found gap, 2026-07-12 — the party was being reseeded
## from scratch on every return, quietly dropping equipped items). See clear_party()/
## clear_return_position() for those halves, called by the destination scene once it's consumed
## them.
func clear_combat_data() -> void:
	enemy_ids = []
	pending_encounter_id = &""
	return_scene_path = ""

## Clears pc/companions/party_inventory/vault — called by the destination scene (e.g.
## overworld_demo.gd's _build_inventory_demo()) once it has reused them as its own live party,
## so a later standalone combat.tscn launch doesn't see stale handoff data and a later return trip
## doesn't re-consume the same references.
func clear_party() -> void:
	pc = null
	companions = []
	party_inventory = null
	vault = null

## Clears return_position/has_return_position — called by the destination scene (e.g.
## overworld_demo.gd's _build_pc()) once it has read them, so a later return trip doesn't reuse a
## stale position.
func clear_return_position() -> void:
	return_position = Vector2.ZERO
	has_return_position = false

## Clears everything the three narrower methods above clear, combined — for callers (and tests)
## that want a full reset in one call. Does NOT clear defeated_encounter_ids — that must persist
## for the life of the session.
func clear_pending() -> void:
	clear_combat_data()
	clear_party()
	clear_return_position()
