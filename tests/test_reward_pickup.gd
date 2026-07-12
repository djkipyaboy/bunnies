extends SceneTree

## RewardPickup: a stationary, contact-triggered overworld pickup — spec
## docs/superpowers/specs/2026-07-11-overworld-npc-encounters-design.md §3.4.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var reward: Gear = Gear.new()
	reward.display_name = "Test Charm"

	var inv: PartyInventory = PartyInventory.new()

	var pickup: RewardPickup = RewardPickup.new()
	pickup.reward_gear = reward
	pickup.party_inventory = inv

	var picked_up_names: Array[String] = []
	pickup.item_picked_up.connect(func(item_name: String) -> void: picked_up_names.append(item_name))

	_check(pickup.auto_trigger == true, "RewardPickup sets auto_trigger true on construction")

	pickup.interact()

	_check(inv.gear.has(reward), "interact() appends reward_gear into the party inventory")
	_check(pickup.is_queued_for_deletion(), "interact() queues the pickup for deletion")
	_check(picked_up_names == ["Test Charm"], "interact() emits item_picked_up with the reward's display_name")

	# queue_free()'s deferred free() never runs without a processed frame (this script never
	# adds pickup to a live tree) — free explicitly, same convention as test_adventuring_board.gd.
	pickup.free()
	quit()
