extends SceneTree

## GatheringNode: a stationary, contact-triggered overworld gathering node (Foraging/Fishing) —
## design-bible 27-crafting.md §11. Mirrors tests/test_reward_pickup.gd almost exactly — interact()
## marks itself defeated in CombatHandoff (same respawn-on-reload fix), which requires this node to
## be a live tree member for _handoff()'s get_node("/root/CombatHandoff") to resolve, so
## CombatHandoff-dependent assertions run in _process()'s first frame (autoloads aren't injected
## yet during a bare SceneTree script's _init()).

var _combat_handoff: Node
var _node: GatheringNode
var _inv: PartyInventory
var _gathered: Array = []   # [{"name": String, "quantity": int}]
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_inv = PartyInventory.new()

	_node = GatheringNode.new()
	_node.name = "TestGatheringNode"
	_node.material_type = &"forage_herb"
	_node.material_display_name = "Wild Berries"
	_node.quantity = 3
	_node.party_inventory = _inv
	root.add_child(_node)

	_node.material_gathered.connect(func(item_name: String, quantity: int) -> void:
		_gathered.append({"name": item_name, "quantity": quantity}))

	_check(_node.auto_trigger == true, "GatheringNode sets auto_trigger true on construction")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		_node.interact()

		_check(_inv.materials.size() == 1, "interact() gives one Material into the party inventory")
		var m: CraftingMaterial = _inv.materials[0]
		_check(m.material_type == &"forage_herb", "the granted Material carries the node's material_type")
		_check(m.display_name == "Wild Berries", "the granted Material carries the node's display name")
		_check(m.quantity == 3, "the granted Material carries the node's quantity")
		_check(_node.is_queued_for_deletion(), "interact() queues the node for deletion")
		_check(_gathered == [{"name": "Wild Berries", "quantity": 3}], "interact() emits material_gathered with the item name and quantity")
		_check(_combat_handoff.is_defeated(&"TestGatheringNode"), "interact() marks its own node name defeated in CombatHandoff")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames >= 3:
		print("ok GatheringNode smoke test complete")
		return true
	return false
