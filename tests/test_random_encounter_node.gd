extends SceneTree

## RandomEncounterNode: a stationary, contact-triggered "?" overworld encounter trigger (player
## direction 2026-07-12). Mirrors tests/test_gathering_node.gd's shape — interact() marks itself
## defeated in CombatHandoff, which requires this node to be a live tree member for _handoff()'s
## get_node("/root/CombatHandoff") to resolve, so CombatHandoff-dependent assertions run in
## _process()'s first frame (autoloads aren't injected yet during a bare SceneTree script's _init()).

var _combat_handoff: Node
var _node: RandomEncounterNode
var _triggered: Array[RandomEncounter] = []
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_node = RandomEncounterNode.new()
	_node.name = "TestEncounterNode"
	_node.encounter_id = &"bandit_ambush"
	root.add_child(_node)

	_node.encounter_triggered.connect(func(encounter: RandomEncounter) -> void: _triggered.append(encounter))

	_check(_node.auto_trigger == true, "RandomEncounterNode sets auto_trigger true on construction")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		_node.interact()

		_check(_triggered.size() == 1, "interact() emits encounter_triggered exactly once")
		_check(_triggered[0].id == &"bandit_ambush", "the emitted RandomEncounter matches the node's encounter_id")
		_check(_node.is_queued_for_deletion(), "interact() queues the node for deletion")
		_check(_combat_handoff.is_defeated(&"TestEncounterNode"), "interact() marks its own node name defeated in CombatHandoff")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames >= 3:
		print("ok RandomEncounterNode smoke test complete")
		return true
	return false
