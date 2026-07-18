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
## Precreated companions available to recruit but not currently in the active party (2026-07-12
## Party Selection work) — rides along with pc/companions/party_inventory/vault everywhere they do
## (stash_party()/begin_encounter()/clear_party()), even though combat itself never reads it (bench
## companions don't fight, so clear_combat_data() deliberately leaves it untouched).
##
## PLAYTEST-FOUND BUG (2026-07-12, fixed same session): begin_encounter() originally had no bench
## param at all, so every real combat encounter silently reset this to [] — by the time the player
## triggered a SECOND fight, _build_inventory_demo() had already consumed+cleared the FIRST
## encounter's bench, and OverworldEnemy's begin_handoff() call never repopulated it. A human
## playtest caught this (companions vanished from Party Selection's Add list after one fight); no
## automated test had exercised a REAL combat round-trip's effect on bench, only SceneExit's.
var bench: Array = []
## The town general store's live stock array (2026-07-17 general store design §3.7) — only
## town_demo.gd ever reads/decrements this; overworld_demo.gd carries it through both directions
## (SceneExit's shop_stock field) without inspecting it, the same asymmetric-ownership shape
## bench/party_inventory/vault already use.
var shop_stock: Array = []
## Which dungeon floor to show on return from a mid-dungeon combat round-trip (2026-07-17
## dungeon-scene-structure design). Only meaningful alongside return_position/has_return_position —
## always read together by dungeon_demo.gd's _determine_start(), so it's cleared in the same place
## return_position is, not via its own dedicated clear method. Irrelevant (stays 0) for any encounter
## that isn't inside the dungeon.
var dungeon_floor: int = 0

## Where to spawn the PC after a PLAIN scene transition (SceneExit, e.g. the dungeon's own exit) —
## the counterpart to return_position/has_return_position, but for the non-combat path. Playtest-
## found bug (2026-07-17): overworld_demo.gd's _build_pc() only ever special-cased return_position,
## so leaving the dungeon always fell back to the single fixed PC_SPAWN constant near the village,
## regardless of which SceneExit was actually used. Set by SceneExit._stash_party() (mirrors
## return_position's ZERO-could-be-legitimate caveat, hence the separate has_ bool), cleared by the
## destination scene once it's read (see clear_entry_spawn_position()).
var entry_spawn_position: Vector2 = Vector2.ZERO
var has_entry_spawn_position: bool = false
var party_inventory: PartyInventory
var vault: Vault
var enemy_ids: Array[StringName] = []
var pending_encounter_id: StringName = &""   # the triggering OverworldEnemy's node name
var return_scene_path: String = ""
var return_position: Vector2 = Vector2.ZERO
var has_return_position: bool = false   # ZERO could be a legitimate spawn point; don't sentinel-compare
var defeated_encounter_ids: Array[StringName] = []
## Which locked gates (e.g. the dungeon's floor-3->4 stairs) have been permanently unlocked this
## session (2026-07-18 lock-and-key design) — separate from whether the party still holds the key
## that unlocked it (the key is consumed on use, but the unlock itself must outlive that, surviving
## any number of scene rebuilds from mid-dungeon combat round-trips). Same session-lifetime
## persistence convention as defeated_encounter_ids — never cleared by clear_pending().
var unlocked_gate_ids: Array[StringName] = []

## Combat-loot items that overflowed the Bag's capacity when a fight ended — carried across the
## combat.tscn -> overworld scene change so the destination scene can drop them as real
## GroundItemPickup nodes at the return position (2026-07-14-ground-item-pickups-design.md §3.4).
## Set by combat.gd BEFORE the scene change; cleared by the destination scene AFTER it reads them —
## same "who clears what and when" convention as return_position/clear_return_position().
var pending_ground_drops: Array[Resource] = []

## Session-lifetime cross-scene history (2026-07-13-overworld-event-log-design.md, categorized
## per 2026-07-13-event-log-tabs-design.md) — a coarse, capped view of notable events (pickups,
## XP, loot, encounters, companion changes), NOT the detailed per-reel combat log (combat.gd's
## own _log_box stays separate/untouched). Persists for the life of the session exactly like
## defeated_encounter_ids above, for the same reason: neither clear_pending() nor its narrower
## siblings below may clear it.
const MAX_EVENT_LOG_LINES: int = 50

## Category tags for the EventLogPanel tab filter (2026-07-13-event-log-tabs-design.md §2/§3).
const CATEGORY_LOOT: StringName = &"loot"
const CATEGORY_COMBAT: StringName = &"combat"
const CATEGORY_PARTY: StringName = &"party"

signal event_logged(line: String, category: StringName)

## Each entry is {"line": String, "category": StringName} — one array of small entries instead
## of two parallel arrays, so trimming/appending can never desync a line from its category.
var event_log_entries: Array[Dictionary] = []

## Appends one entry, trimming the OLDEST entry once the cap is exceeded, and notifies any open
## EventLogPanel via event_logged so it can append live instead of re-rendering from scratch.
func log_event(line: String, category: StringName) -> void:
	event_log_entries.append({"line": line, "category": category})
	if event_log_entries.size() > MAX_EVENT_LOG_LINES:
		event_log_entries.pop_front()
	event_logged.emit(line, category)

## Carries the party across a plain cross-scene transition (SceneExit, e.g. town<->overworld) —
## no combat/return-position fields involved, unlike begin_encounter(). The destination scene reads
## pc/companions/party_inventory/vault the same way it already does for a combat return trip
## (checks pc != null, reuses, then calls clear_party()).
func stash_party(p: Combatant, comps: Array, inv: PartyInventory, v: Vault, b: Array = [], shop: Array = [],
		spawn: Vector2 = Vector2.ZERO, has_spawn: bool = false) -> void:
	pc = p
	companions = comps
	bench = b
	party_inventory = inv
	vault = v
	shop_stock = shop
	entry_spawn_position = spawn
	has_entry_spawn_position = has_spawn

func begin_encounter(p: Combatant, comps: Array, inv: PartyInventory, v: Vault,
		ids: Array[StringName], encounter_id: StringName, scene_path: String, position: Vector2,
		b: Array = [], shop: Array = [], floor: int = 0) -> void:
	pc = p
	companions = comps
	bench = b
	party_inventory = inv
	vault = v
	enemy_ids = ids
	pending_encounter_id = encounter_id
	return_scene_path = scene_path
	return_position = position
	has_return_position = true
	shop_stock = shop
	dungeon_floor = floor

func mark_defeated(encounter_id: StringName) -> void:
	if not defeated_encounter_ids.has(encounter_id):
		defeated_encounter_ids.append(encounter_id)

func is_defeated(encounter_id: StringName) -> bool:
	return defeated_encounter_ids.has(encounter_id)

func mark_gate_unlocked(gate_id: StringName) -> void:
	if not unlocked_gate_ids.has(gate_id):
		unlocked_gate_ids.append(gate_id)

func is_gate_unlocked(gate_id: StringName) -> bool:
	return unlocked_gate_ids.has(gate_id)

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
	bench = []
	party_inventory = null
	vault = null
	shop_stock = []

## Clears return_position/has_return_position — called by the destination scene (e.g.
## overworld_demo.gd's _build_pc()) once it has read them, so a later return trip doesn't reuse a
## stale position.
func clear_return_position() -> void:
	return_position = Vector2.ZERO
	has_return_position = false
	dungeon_floor = 0

## Clears pending_ground_drops — called by the destination scene (overworld_demo.gd) once it has
## spawned GroundItemPickup nodes for them.
func clear_ground_drops() -> void:
	pending_ground_drops = [] as Array[Resource]

## Clears entry_spawn_position/has_entry_spawn_position — called by the destination scene (e.g.
## overworld_demo.gd's _build_pc()) once it has read them, so a later plain-transition entry doesn't
## reuse a stale spawn point from a different SceneExit.
func clear_entry_spawn_position() -> void:
	entry_spawn_position = Vector2.ZERO
	has_entry_spawn_position = false

## Clears everything the five narrower methods above clear, combined — for callers (and tests)
## that want a full reset in one call. Does NOT clear defeated_encounter_ids or event_log_entries —
## both must persist for the life of the session.
func clear_pending() -> void:
	clear_combat_data()
	clear_party()
	clear_return_position()
	clear_ground_drops()
	clear_entry_spawn_position()
