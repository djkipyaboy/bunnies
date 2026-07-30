class_name SceneExit
extends Interactable

## A cross-scene "leaves to a different scene" interactable
## (2026-07-08-overworld-demo-prototype-design.md §4) — used for both the overworld's
## VillageEntrance (target: town_demo.tscn) and the town's TownExit (target:
## overworld_demo.tscn). Reuses Interactable's highlight_visual/set_highlighted() for the
## same dim/bright arrow behavior the shop's exit arrow already has, with zero new code.
##
## Unlike Door, there's no single universal prompt_text ("Open" fits every door; "Enter
## Village" and "Leave Town" don't share a word) — callers set prompt_text explicitly per
## instance instead of this class hardcoding one in _init().
##
## Also carries the current party across the transition (2026-07-12 shared-party-state work) —
## stashes it into CombatHandoff (the project's one cross-scene persistence point) before the
## scene change, mirroring the pattern combat.gd already uses to hand the fought party back to
## the overworld. Placement-time fields, same convention as Door.pc/OverworldEnemy's fields.

## res:// path to the scene this transitions to.
@export var target_scene_path: String = ""

## The scene's FadeOverlay — interact() awaits its fade_out() before swapping scenes.
@export var fade_overlay: FadeOverlay

## Wired externally by whoever places this (mirrors OverworldEnemy's pc_combatant/companions/
## party_inventory/vault fields) — the current scene's live party, carried to the destination.
var pc_combatant: Combatant
var companions: Array = []
## Precreated companions available to recruit but not currently in the active party (2026-07-12
## Party Selection work) — carried alongside companions so the bench survives a scene transition.
var bench: Array = []
## Only meaningful for the town's TownExit instance (only town has a shop) — VillageEntrance
## carries whatever CombatHandoff last gave it through without ever needing to inspect it.
var shop_stock: Array = []
var party_inventory: PartyInventory
var vault: Vault

## Where the destination scene should spawn the PC (2026-07-17 playtest-found fix) — settable
## per-instance by whoever places this SceneExit, e.g. the dungeon's DungeonExit points back at the
## mountain entrance instead of the destination scene's generic default spawn. Left unset (false) by
## every pre-existing placement (VillageEntrance/TownExit), which keeps relying on the destination
## scene's own default spawn exactly as before.
@export var target_spawn_position: Vector2 = Vector2.ZERO
@export var has_target_spawn_position: bool = false

## Opt-in (2026-07-29 UTIL-reel jackpot spec §2): rounds the party's Jackpot Meter down to its
## nearest checkpoint on departure. Defaults false so every pre-existing SceneExit placement
## (VillageEntrance, TownExit) is unaffected — only the dungeon's own exit sets this true, since the
## spec ties the rounddown specifically to "leaving a dungeon," not every scene transition.
@export var rounds_down_jackpot: bool = false

func interact() -> void:
	_stash_party()
	await fade_overlay.fade_out()
	get_tree().change_scene_to_file(target_scene_path)

## Split out from interact() so tests can drive the CombatHandoff-population effect without
## triggering the fade + change_scene_to_file (same reasoning as OverworldEnemy._begin_handoff()).
func _stash_party() -> void:
	if rounds_down_jackpot and party_inventory != null:
		party_inventory.round_down_jackpot_to_checkpoint()
	_handoff().stash_party(pc_combatant, companions, party_inventory, vault, bench, shop_stock,
		target_spawn_position, has_target_spawn_position)

## Fetches the CombatHandoff autoload by path — see OverworldEnemy._handoff()'s identical
## rationale (bare `CombatHandoff` identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
