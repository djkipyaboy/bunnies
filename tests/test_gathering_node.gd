extends SceneTree

## GatheringNode: a stationary, contact-triggered overworld gathering node (Foraging) -- 2026-08-01
## gathering-profession-minigames spec section 2. Now HANDS OFF to the driving scene's ForagingPanel
## instead of granting a material directly (mirrors RandomEncounterNode's shape, not RewardPickup's
## self-contained-resolution shape) -- interact() marks itself defeated in CombatHandoff (same
## respawn-on-reload fix as before) and frees itself, since the encounter has started regardless of
## what the player does in the panel afterward.

var _combat_handoff: Node
var _node: GatheringNode
var _requested: Array = []   # [{"material_type": StringName, "material_display_name": String, "quantity": int}]
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_node = GatheringNode.new()
	_node.name = "TestGatheringNode"
	_node.material_type = &"forage_herb"
	_node.material_display_name = "Wild Berries"
	_node.quantity = 3
	root.add_child(_node)

	_node.foraging_requested.connect(func(material_type: StringName, material_display_name: String, quantity: int) -> void:
		_requested.append({"material_type": material_type, "material_display_name": material_display_name, "quantity": quantity}))

	_check(_node.auto_trigger == true, "GatheringNode sets auto_trigger true on construction")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		_node.interact()

		_check(_requested == [{"material_type": &"forage_herb", "material_display_name": "Wild Berries", "quantity": 3}],
			"interact() emits foraging_requested with the node's material_type/display_name/quantity")
		_check(_node.is_queued_for_deletion(), "interact() queues the node for deletion")
		_check(_combat_handoff.is_defeated(&"TestGatheringNode"), "interact() marks its own node name defeated in CombatHandoff")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames >= 3:
		print("ok GatheringNode smoke test complete")
		return true
	return false
