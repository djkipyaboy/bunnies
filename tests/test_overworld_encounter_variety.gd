extends SceneTree

## Integration test for the 2026-07-12 "overworld encounter variety" work: the real BanditAmbush
## RandomEncounterNode, triggered through overworld_demo.gd's actual _process()/interact() wiring
## (not a hand-built panel like tests/test_random_encounter_panel.gd's unit coverage, which uses
## deterministic single-tier reels for the outcome-application logic itself). The real
## EncounterLibrary reels ARE randomized, so this file only asserts structure (movement pause,
## panel open/close, defeated-tracking) — not which of the 3 outcome buckets lands — mirroring
## test_overworld_demo_npcs.gd's existing RewardPickup/GatheringNode integration-test style.

var _instance: Node
var _combat_handoff: Node
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
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		var overworld: OverworldDemo = _instance
		# This test never moves the PC's global_position, so the 2026-07-17/18
		# AUTO_TRIGGER_ARM_DISTANCE gate (overworld_demo.gd) would otherwise permanently block
		# BanditAmbush's auto_trigger — arm it directly, the same way this test already reaches
		# into other private PC/overworld state.
		overworld._auto_trigger_armed = true
		var encounter_node: RandomEncounterNode = overworld._world.get_node("BanditAmbush")

		# Force the node into reach and drive one real _process() frame — mirrors
		# test_overworld_demo_npcs.gd's RewardPickup/GatheringNode auto_trigger drive.
		overworld._pc._tracked.append(encounter_node)
		overworld._process(0.016)

		_check(encounter_node.is_queued_for_deletion(), "touching BanditAmbush queues the node for deletion")
		_check(_combat_handoff.is_defeated(&"BanditAmbush"), "touching BanditAmbush marks it defeated")
		_check(overworld._random_encounter_panel.is_open(), "the encounter panel opens on trigger")
		_check(overworld._pc.movement_paused_for_test(), "PC movement pauses while the encounter panel is open")
		overworld._pc._tracked.erase(encounter_node)

		# Choosing an option resolves the real (randomized) reel — assert the STRUCTURE of the
		# outcome, not which bucket landed (that's test_random_encounter_panel.gd's job).
		overworld._random_encounter_panel.press_option_for_test(0)
		_check(overworld._random_encounter_panel.is_resolved_for_test(), "pressing an option resolves the real encounter")
		_check(not overworld._random_encounter_panel.result_text_for_test().is_empty(), "a non-empty result is shown after resolving")

		overworld._random_encounter_panel.press_continue_for_test()
		_check(not overworld._random_encounter_panel.is_open(), "pressing Continue closes the encounter panel")
		_check(not overworld._pc.movement_paused_for_test(), "closing the encounter panel resumes PC movement")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames == 2:
		# --- Defeated-encounter skip: same convention as OverworldRat/ShinyTrinket/WildBerries. ---
		_combat_handoff.mark_defeated(&"BanditAmbush")

		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		var defeated_instance: OverworldDemo = scene.instantiate()
		root.add_child(defeated_instance)
		_check(defeated_instance._world.get_node_or_null("BanditAmbush") == null, "an already-triggered BanditAmbush is skipped on scene rebuild")
		defeated_instance.free()

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]
		_instance.free()

	if _frames >= 5:
		print("ok overworld encounter variety smoke test complete")
		return true
	return false
