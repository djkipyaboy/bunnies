extends SceneTree

## RewardPickup: a stationary, contact-triggered overworld pickup — spec
## docs/superpowers/specs/2026-07-11-overworld-npc-encounters-design.md §3.4.
## interact() now marks itself defeated in CombatHandoff (2026-07-12 respawn-on-reload fix, mirrors
## OverworldEnemy's defeated-tracking). Autoloads (CombatHandoff included) aren't injected into the
## tree yet during a bare SceneTree script's _init() — confirmed empirically, matches
## tests/test_overworld_demo_npcs.gd's own note — so the CombatHandoff-dependent assertions run in
## _process()'s first frame instead.

var _combat_handoff: Node
var _pickup: RewardPickup
var _inv: PartyInventory
var _reward: Gear
var _picked_up_names: Array[String] = []
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_reward = Gear.new()
	_reward.display_name = "Test Charm"

	_inv = PartyInventory.new()

	_pickup = RewardPickup.new()
	_pickup.name = "TestPickup"
	_pickup.reward_gear = _reward
	_pickup.party_inventory = _inv
	root.add_child(_pickup)

	_pickup.item_picked_up.connect(func(item_name: String) -> void: _picked_up_names.append(item_name))

	_check(_pickup.auto_trigger == true, "RewardPickup sets auto_trigger true on construction")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		_pickup.interact()

		_check(_inv.gear.has(_reward), "interact() appends reward_gear into the party inventory")
		_check(_pickup.is_queued_for_deletion(), "interact() queues the pickup for deletion")
		_check(_picked_up_names == ["Test Charm"], "interact() emits item_picked_up with the reward's display_name")
		_check(_combat_handoff.is_defeated(&"TestPickup"), "interact() marks its own node name defeated in CombatHandoff")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames >= 3:
		print("ok RewardPickup smoke test complete")
		return true
	return false
