extends SceneTree

## End-to-end regression for the 2026-07-12 shared-party-state work: town_demo.tscn and
## overworld_demo.tscn used to each seed their own independent placeholder party
## (InventoryDemoSetup.seed_demo_party()) — this proves a SceneExit transition (TownExit /
## VillageEntrance) now carries the SAME live party across the round trip, town -> overworld ->
## town, the same way combat.gd's Continue handler already does for the overworld <-> combat leg.
## Uses the exact real call sequence a player's transition drives:
## SceneExit._stash_party() (what interact() calls, minus the fade/scene-change side effects a
## test shouldn't trigger — same reasoning as OverworldEnemy._begin_handoff()) -> a fresh scene
## instance's _build_inventory_demo() consuming CombatHandoff.pc.

var _combat_handoff: Node
var _town_instance: Node
var _overworld_instance: Node
var _town_instance_2: Node
var _distinctive_gear: Gear
var _recruited: Combatant
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		var town: TownDemo = _town_instance
		# Give the freshly-seeded PC a distinctive piece of gear so later assertions prove the
		# EXACT Combatant survives, not just that some Combatant exists.
		_distinctive_gear = Gear.new()
		_distinctive_gear.display_name = "Well-Traveled Cloak"
		_distinctive_gear.slot = Gear.Slot.CLOAK
		_distinctive_gear.stat_bonuses = Stats.new()
		town._pc_combatant.gear = [_distinctive_gear]

		_check(town._town_exit.pc_combatant == town._pc_combatant, "TownExit is wired to the town's live PC")
		_check(town._town_exit.party_inventory == town._party_inventory, "TownExit is wired to the town's live PartyInventory")
		_check(town._town_exit.bench == town._bench, "TownExit is wired to the town's live bench (same array reference)")

		# Recruit a companion via the real Party Selection code path (2026-07-12) so the round trip
		# also proves _companions/_bench mutations survive, not just the initial seed.
		_check(town._bench.size() > 0, "the demo seeds a non-empty bench of precreated companions")
		_recruited = town._bench[0]
		town._on_add_companion_requested(_recruited)
		_check(town._companions.has(_recruited), "_on_add_companion_requested moves the recruit into _companions")
		_check(not town._bench.has(_recruited), "_on_add_companion_requested removes the recruit from _bench")
		_check(town._town_exit.companions.has(_recruited), "TownExit's companions field reflects the recruit (same array reference)")

		# Simulate leaving town via TownExit (without the fade/scene-change side effects).
		town._town_exit._stash_party()
		_check(_combat_handoff.pc == town._pc_combatant, "leaving town stashes the exact PC into CombatHandoff")
		_check(_combat_handoff.companions.has(_recruited), "leaving town stashes the recruited companion into CombatHandoff.companions")

	if _frames == 2:
		var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = overworld_scene.instantiate()
		root.add_child(_overworld_instance)

		var overworld: OverworldDemo = _overworld_instance
		_check(overworld._pc_combatant.gear.has(_distinctive_gear), "overworld reuses the town's exact PC (gear survives the transition)")
		_check(_combat_handoff.pc == null, "overworld_demo consumed and cleared CombatHandoff.pc")
		_check(overworld._village_entrance.pc_combatant == overworld._pc_combatant, "VillageEntrance is wired to the overworld's (reused) live PC")
		_check(overworld._companions.has(_recruited), "the overworld reuses the recruited companion (not just the original party)")
		_check(not overworld._bench.has(_recruited), "the recruited companion doesn't ALSO show up back on the overworld's bench")

		# Simulate leaving the overworld back to town via VillageEntrance.
		overworld._village_entrance._stash_party()
		_check(_combat_handoff.pc == overworld._pc_combatant, "leaving the overworld stashes the same PC back into CombatHandoff")

	if _frames == 3:
		var town_scene_2: PackedScene = load("res://world/town_demo.tscn")
		_town_instance_2 = town_scene_2.instantiate()
		root.add_child(_town_instance_2)

		var town_2: TownDemo = _town_instance_2
		_check(town_2._pc_combatant.gear.has(_distinctive_gear), "returning to town reuses the exact same PC (gear survives the full round trip)")
		_check(_combat_handoff.pc == null, "town_demo consumed and cleared CombatHandoff.pc")
		_check(town_2._companions.has(_recruited), "the recruited companion survives the full round trip (town -> overworld -> town)")

		_town_instance.free()
		_overworld_instance.free()
		_town_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 6:
		print("ok shared party state round-trip regression complete")
		return true
	return false
