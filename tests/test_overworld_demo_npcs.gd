extends SceneTree

## Headless smoke test for the overworld NPC encounters wiring (spec 2026-07-11-overworld-npc-
## encounters-design.md §3.6, plan Task 5). Confirms the three placeholder NPCs (OverworldEnemy,
## RewardPickup, friendly Villager) exist as children of _world after _ready(), and drives the
## real _process()/dialogue paths end-to-end (not just unit-level) the same way
## tests/test_town_demo_inventory.gd exercises town_demo.gd.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var overworld: OverworldDemo = _instance

		var enemy_node: OverworldEnemy = overworld._world.get_node("OverworldRat")
		var reward_node: RewardPickup = overworld._world.get_node("ShinyTrinket")
		var wanderer_node: Villager = overworld._world.get_node("OverworldWanderer")
		_check(enemy_node != null, "OverworldEnemy exists as a child of _world")
		_check(reward_node != null, "RewardPickup exists as a child of _world")
		_check(wanderer_node != null, "friendly Villager exists as a child of _world")

		# --- OverworldEnemy: force it into interaction reach, drive one real _process() frame,
		# confirm the auto-trigger branch fires it end-to-end (not just at the unit level). ---
		var enemy_zone: Interactable = enemy_node.get_node("InteractionZone")
		overworld._pc._tracked.append(enemy_zone)
		overworld._process(0.016)
		_check(enemy_node.is_queued_for_deletion(), "touching the OverworldEnemy queues it for deletion")
		_check(overworld._encounter_debug_label.text.find("rat") != -1, "debug label mentions the triggered enemy id")
		overworld._pc._tracked.erase(enemy_zone)

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
		overworld._pc._tracked.erase(reward_node)

		# --- Regression (2026-07-11 final review, Important finding): a same-frame interact
		# keypress must NOT double-fire an auto_trigger target alongside _process's own
		# auto-fire — queue_free() is deferred, so without the _unhandled_input guard the
		# reward would be granted twice / the encounter signal would emit twice. ---
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
	if _frames >= 5:
		print("ok overworld_demo NPC encounters smoke test complete")
		_instance.free()
		return true
	return false
