extends SceneTree

## FishingSpot: a stationary, contact-triggered overworld fishing node (2026-08-01
## gathering-profession-minigames spec section 3). HANDS OFF to the driving scene's FishingPanel on
## interact() (mirrors GatheringNode/RandomEncounterNode's shape) -- marks itself defeated in
## CombatHandoff and frees itself, carrying one material config PER shadow-size bucket since real
## fish content doesn't exist yet.

var _combat_handoff: Node
var _node: FishingSpot
var _requested: Array = []   # [Dictionary] -- the bucket_configs payload from each emit
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_node = FishingSpot.new()
	_node.name = "TestFishingSpot"
	_node.small_material_type = &"fish_small"
	_node.small_material_display_name = "Minnow"
	_node.small_quantity = 1
	_node.medium_material_type = &"fish_medium"
	_node.medium_material_display_name = "Freshwater Fish"
	_node.medium_quantity = 1
	_node.large_material_type = &"fish_large"
	_node.large_material_display_name = "Prize Bass"
	_node.large_quantity = 1
	root.add_child(_node)

	_node.fishing_requested.connect(func(bucket_configs: Dictionary) -> void:
		_requested.append(bucket_configs))

	_check(_node.auto_trigger == true, "FishingSpot sets auto_trigger true on construction")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		_node.interact()

		_check(_requested.size() == 1, "interact() emits fishing_requested exactly once")
		var configs: Dictionary = _requested[0]
		_check(configs[&"small"] == {"material_type": &"fish_small", "material_display_name": "Minnow", "quantity": 1},
			"the small bucket's config matches the node's authored fields, got %s" % str(configs[&"small"]))
		_check(configs[&"medium"] == {"material_type": &"fish_medium", "material_display_name": "Freshwater Fish", "quantity": 1},
			"the medium bucket's config matches the node's authored fields, got %s" % str(configs[&"medium"]))
		_check(configs[&"large"] == {"material_type": &"fish_large", "material_display_name": "Prize Bass", "quantity": 1},
			"the large bucket's config matches the node's authored fields, got %s" % str(configs[&"large"]))
		_check(_node.is_queued_for_deletion(), "interact() queues the node for deletion")
		_check(_combat_handoff.is_defeated(&"TestFishingSpot"), "interact() marks its own node name defeated in CombatHandoff")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames >= 3:
		print("ok FishingSpot smoke test complete")
		return true
	return false
