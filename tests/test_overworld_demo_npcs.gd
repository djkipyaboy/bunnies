extends SceneTree

## Headless smoke test for the overworld NPC encounters wiring. Confirms the three placeholder
## NPCs (OverworldEnemy, RewardPickup, friendly Villager) exist as children of _world after
## _ready(), drives the real _process()/dialogue paths for RewardPickup/Villager end-to-end (same
## as before), and now also confirms the OverworldEnemy <-> CombatHandoff wiring plus the two
## round-trip behaviors added in 2026-07-11-overworld-combat-handoff-design.md §3.3/§3.5:
## an already-defeated encounter is skipped on rebuild, and the PC spawns at
## CombatHandoff.return_position when set.
##
## NOTE: this file does NOT drive OverworldEnemy's real interact() — _on_interacted() now awaits
## a fade then calls get_tree().change_scene_to_file("res://combat/combat.tscn"), and actually
## triggering that here would try to load combat.tscn into this test's own SceneTree, which is
## undesirable. The CombatHandoff-population behavior on trigger is already covered directly by
## tests/test_overworld_enemy.gd (which calls enemy._begin_handoff() without the fade/scene-change
## piece). This file only asserts the *wiring* — that _build_npcs() sets the right fields on the
## placed enemy instance — plus the _build_npcs()/_build_pc() behaviors that read CombatHandoff.
##
## CombatHandoff is an autoload; a bare `extends SceneTree` test script doesn't get the same
## autoload injection a normal scene does, so it's fetched via get_root().get_node("CombatHandoff")
## (confirmed pattern, see tests/test_combat_handoff.gd) rather than referenced as a bare
## identifier. Since it's a singleton that persists for this whole script's run, state is reset
## between sections so one section's setup doesn't leak into the next.

var _instance: Node
var _frames: int = 0
var _combat_handoff: Node

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		var overworld: OverworldDemo = _instance

		var enemy_node: OverworldEnemy = overworld._world.get_node("OverworldRat")
		var reward_node: RewardPickup = overworld._world.get_node("ShinyTrinket")
		var wanderer_node: Villager = overworld._world.get_node("OverworldWanderer")
		var berries_node: GatheringNode = overworld._world.get_node("WildBerries")
		var fish_node: GatheringNode = overworld._world.get_node("FishingSpot")
		var ferret_node: OverworldEnemy = overworld._world.get_node("OverworldFerret")
		var stoat_node: OverworldEnemy = overworld._world.get_node("OverworldStoat")
		var encounter_node: RandomEncounterNode = overworld._world.get_node("BanditAmbush")
		_check(enemy_node != null, "OverworldEnemy exists as a child of _world")
		_check(reward_node != null, "RewardPickup exists as a child of _world")
		_check(wanderer_node != null, "friendly Villager exists as a child of _world")
		_check(berries_node != null, "the Foraging GatheringNode (WildBerries) exists as a child of _world")
		_check(fish_node != null, "the Fishing GatheringNode (FishingSpot) exists as a child of _world")
		_check(berries_node.party_inventory == overworld._party_inventory, "WildBerries.party_inventory wired to the scene's live PartyInventory")
		_check(ferret_node != null and ferret_node.enemy_ids == [&"ferret"], "OverworldFerret is placed with the ferret roster (2026-07-12 encounter variety)")
		_check(stoat_node != null and stoat_node.enemy_ids == [&"stoat"], "OverworldStoat is placed with the stoat roster (2026-07-12 encounter variety)")
		_check(encounter_node != null and encounter_node.encounter_id == &"bandit_ambush", "the BanditAmbush RandomEncounterNode is placed (2026-07-12 '?' encounters)")

		# --- OverworldEnemy <-> CombatHandoff wiring: _build_npcs() sets the placement-time
		# fields that feed CombatHandoff.begin_encounter() on trigger (not triggered here, see
		# the note above). ---
		_check(enemy_node.fade_overlay == overworld._fade_overlay, "OverworldEnemy.fade_overlay wired to the scene's FadeOverlay")
		_check(enemy_node.pc_combatant == overworld._pc_combatant, "OverworldEnemy.pc_combatant wired to the scene's PC combatant")
		_check(enemy_node.companions == overworld._companions, "OverworldEnemy.companions wired to the scene's companions")
		_check(enemy_node.party_inventory == overworld._party_inventory, "OverworldEnemy.party_inventory wired")
		_check(enemy_node.vault == overworld._vault, "OverworldEnemy.vault wired")
		_check(enemy_node.return_scene_path == "res://world/overworld_demo.tscn", "OverworldEnemy.return_scene_path wired")
		_check(enemy_node.pc_node == overworld._pc, "OverworldEnemy.pc_node wired to the scene's PC node")

		# --- Friendly Villager: dialogue opens via _on_dialogue_requested and pauses PC movement,
		# closing resumes it — mirrors test_town_demo_inventory.gd's dialogue assertions. ---
		overworld._on_dialogue_requested(wanderer_node.dialogue, wanderer_node)
		_check(overworld._dialogue_box.is_open(), "dialogue opens for the friendly Villager")
		_check(overworld._pc.movement_paused_for_test(), "dialogue request pauses PC movement")
		overworld._dialogue_box.close()
		_check(not overworld._pc.movement_paused_for_test(), "dialogue close resumes PC movement")

		# --- RewardPickup: force it into reach, drive one real _process() frame, confirm the
		# reward lands in _party_inventory and the node frees itself. ---
		overworld._pc._tracked.append(reward_node)
		overworld._process(0.016)
		_check(overworld._party_inventory.gear.has(reward_node.reward_gear), "RewardPickup's gear lands in _party_inventory")
		_check(reward_node.is_queued_for_deletion(), "touching the RewardPickup queues it for deletion")
		_check(overworld._pickup_debug_label.text.find("Shiny Trinket") != -1, "pickup debug label mentions the collected item's name")
		overworld._pc._tracked.erase(reward_node)

		# --- GatheringNode (WildBerries): force it into reach, drive one real _process() frame,
		# confirm the Material lands in _party_inventory and the node frees itself. ---
		overworld._pc._tracked.append(berries_node)
		overworld._process(0.016)
		_check(overworld._party_inventory.materials.size() == 1, "touching WildBerries gives one Material into _party_inventory")
		_check(overworld._party_inventory.materials[0].material_type == &"forage_herb", "the granted Material carries WildBerries' material_type")
		_check(berries_node.is_queued_for_deletion(), "touching WildBerries queues it for deletion")
		_check(overworld._pickup_debug_label.text.find("Wild Berries") != -1, "pickup debug label mentions the gathered material's name")
		overworld._pc._tracked.erase(berries_node)

		# --- Regression (2026-07-11 final review, Important finding): a same-frame interact
		# keypress must NOT double-fire an auto_trigger target alongside _process's own
		# auto-fire — queue_free() is deferred, so without the _unhandled_input guard the
		# reward would be granted twice. ---
		var reward_node_2 := RewardPickup.new()
		var second_gear := Gear.new()
		second_gear.display_name = "Second Trinket"
		second_gear.stat_bonuses = Stats.new()
		reward_node_2.reward_gear = second_gear
		reward_node_2.party_inventory = overworld._party_inventory
		overworld._world.add_child(reward_node_2)
		overworld._pc._tracked.append(reward_node_2)
		var interact_event := InputEventAction.new()
		interact_event.action = &"interact"
		interact_event.pressed = true
		overworld._unhandled_input(interact_event)
		overworld._process(0.016)
		var grant_count: int = overworld._party_inventory.gear.filter(func(g: Gear) -> bool: return g == second_gear).size()
		_check(grant_count == 1, "a same-frame interact keypress does not double-grant an auto_trigger RewardPickup's reward")

	if _frames == 5:
		# Give the deferred queue_free() calls above a few idle frames to actually process
		# before tearing down the whole instance (matches this file's prior convention).
		_instance.free()

	if _frames == 6:
		# --- Defeated-encounter skip: mark "OverworldRat" defeated BEFORE a fresh scene load,
		# confirm _build_npcs() skips creating it. This is a brand-new scene instance (own
		# CombatHandoff.is_defeated check happens in THAT instance's _ready()). ---
		_combat_handoff.clear_pending()
		# A fresh Array literal each time — reusing the same array reference across an assignment
		# and a mark_defeated() append would alias, making the later "reset" a no-op (mutating the
		# same backing array both times, since GDScript Arrays are reference types).
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]
		_combat_handoff.mark_defeated(&"OverworldRat")

		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		var defeated_instance: OverworldDemo = scene.instantiate()
		root.add_child(defeated_instance)
		_check(defeated_instance._world.get_node_or_null("OverworldRat") == null, "an already-defeated OverworldRat is skipped on scene rebuild")
		defeated_instance.free()

		# --- Same skip behavior for a collected RewardPickup (2026-07-12 respawn-on-reload fix) —
		# mirrors OverworldEnemy's defeated-tracking exactly, keyed off RewardPickup's own node name
		# ("ShinyTrinket") rather than an enemy id. ---
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]
		_combat_handoff.mark_defeated(&"ShinyTrinket")

		var reward_scene: PackedScene = load("res://world/overworld_demo.tscn")
		var reward_defeated_instance: OverworldDemo = reward_scene.instantiate()
		root.add_child(reward_defeated_instance)
		_check(reward_defeated_instance._world.get_node_or_null("ShinyTrinket") == null, "an already-collected ShinyTrinket is skipped on scene rebuild")
		reward_defeated_instance.free()

		# --- Same skip behavior for a gathered GatheringNode (2026-07-12 §11 work) — mirrors
		# RewardPickup's defeated-tracking exactly. ---
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]
		_combat_handoff.mark_defeated(&"WildBerries")

		var berries_scene: PackedScene = load("res://world/overworld_demo.tscn")
		var berries_defeated_instance: OverworldDemo = berries_scene.instantiate()
		root.add_child(berries_defeated_instance)
		_check(berries_defeated_instance._world.get_node_or_null("WildBerries") == null, "an already-gathered WildBerries is skipped on scene rebuild")
		berries_defeated_instance.free()

		# Reset before the next section so the defeated-mark doesn't leak into it.
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames == 7:
		# --- return_position spawn: with CombatHandoff.has_return_position set BEFORE scene
		# load, the PC spawns there instead of the hardcoded PC_SPAWN constant. ---
		var distinctive_position := Vector2(999.0, 111.0)
		_combat_handoff.has_return_position = true
		_combat_handoff.return_position = distinctive_position

		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		var return_instance: OverworldDemo = scene.instantiate()
		root.add_child(return_instance)
		_check(return_instance._pc.global_position == distinctive_position, "PC spawns at CombatHandoff.return_position when set")
		# _build_pc() should have consumed and cleared the return position (final-review fix,
		# 2026-07-11) so a LATER round trip doesn't reuse this stale position.
		_check(not _combat_handoff.has_return_position, "_build_pc() clears has_return_position after reading it")
		return_instance.free()

		# Clean slate — don't leave pending handoff state hanging around after this script exits.
		_combat_handoff.clear_pending()

	if _frames == 8:
		# --- Full cross-scene regression (2026-07-11 final review Critical finding, extended
		# 2026-07-12 for the party-persistence gap): the exact sequence combat.gd's Continue
		# handler now runs — begin_encounter() populates the handoff, then clear_combat_data()
		# (NOT clear_pending()) wipes only the combat-specific fields, leaving BOTH
		# return_position/has_return_position AND the party (pc/companions/party_inventory/vault)
		# intact for the overworld to read/reuse. Give the fought PC a distinctive piece of gear
		# BEFORE the handoff so this test actually proves gear survives the round trip, not just
		# that some Combatant object exists — playtest-found gap, 2026-07-12: the overworld used to
		# unconditionally reseed a brand-new placeholder party on every load, silently discarding
		# whatever was equipped before the fight. ---
		var fought_pos := Vector2(321.0, 654.0)
		var fought_ids: Array[StringName] = [&"rat"]
		var fought_pc := Combatant.new()
		var distinctive_gear := Gear.new()
		distinctive_gear.display_name = "Fought-In Helmet"
		distinctive_gear.slot = Gear.Slot.HEADWEAR
		distinctive_gear.stat_bonuses = Stats.new()
		fought_pc.gear = [distinctive_gear]
		var fought_inv := PartyInventory.new()
		var fought_vault := Vault.new()
		_combat_handoff.begin_encounter(fought_pc, [], fought_inv, fought_vault,
			fought_ids, &"OverworldRat", "res://world/overworld_demo.tscn", fought_pos)
		_combat_handoff.clear_combat_data()   # what combat.gd's Continue handler calls, not clear_pending()
		_check(_combat_handoff.has_return_position, "clear_combat_data leaves has_return_position set for the destination scene to read")
		_check(_combat_handoff.pc == fought_pc, "clear_combat_data leaves the party intact for the overworld to reuse")

		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		var round_trip_instance: OverworldDemo = scene.instantiate()
		root.add_child(round_trip_instance)
		_check(round_trip_instance._pc.global_position == fought_pos, "after combat.gd's real clear_combat_data() call, the overworld still spawns the PC at the pre-fight position")
		_check(round_trip_instance._pc_combatant == fought_pc, "the overworld reuses the EXACT fought Combatant, not a freshly reseeded one")
		_check(round_trip_instance._pc_combatant.gear.has(distinctive_gear), "gear equipped before the fight is still equipped after returning from combat")
		_check(_combat_handoff.pc == null, "_build_inventory_demo() clears the handoff's party reference once it's reused it")
		round_trip_instance.free()
		_combat_handoff.clear_pending()

	if _frames >= 12:
		print("ok overworld_demo NPC encounters smoke test complete")
		return true
	return false
