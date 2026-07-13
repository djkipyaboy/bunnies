extends SceneTree

# Headless test: OverworldEnemy composes an auto-triggering, contact-sized Interactable and,
# on trigger, populates CombatHandoff with the placement-time party/enemy data instead of
# emitting a signal and freeing itself.
# Spec: docs/superpowers/specs/2026-07-11-overworld-combat-handoff-design.md §3.2.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_enemy.gd
#
# CombatHandoff is registered as an autoload in project.godot, but an `extends SceneTree` headless
# test script does NOT get the same autoload injection a normal scene does — reference it via
# get_root().get_node("CombatHandoff") once the tree exists (confirmed pattern, see
# tests/test_combat_handoff.gd), not the bare identifier.
#
# _on_interacted() now does `_begin_handoff()` (populates CombatHandoff) then
# `await fade_overlay.fade_out()` followed by `get_tree().change_scene_to_file(...)`. Actually
# letting that run in this bare test would try to swap the TEST RUNNER's own "scene" mid-test,
# which is undesirable. Rather than exercise the fade/scene-change at all, this test calls
# `_begin_handoff()` directly (the small function overworld_enemy.gd split out for exactly this
# purpose) — it's the entire piece of behavior this test cares about; the fade+scene-change
# lines are identical boilerplate already proven by scene_exit.gd/its own tests.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

var _enemy: OverworldEnemy
var _pc_node: Node2D

func _init() -> void:
	_enemy = OverworldEnemy.new()
	_enemy.name = "TestEnemy"
	_enemy.enemy_ids = [&"rat"]
	root.add_child(_enemy)

	_pc_node = Node2D.new()
	_pc_node.global_position = Vector2(321.0, 654.0)
	root.add_child(_pc_node)

func _process(_delta: float) -> bool:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")

	var enemy: OverworldEnemy = _enemy
	var zone: Interactable = enemy.get_node("InteractionZone")
	_check(zone != null, "OverworldEnemy composes an InteractionZone Interactable child")
	_check(zone.auto_trigger == true, "the composed Interactable has auto_trigger == true")
	_check(zone.interaction_radius == 10.0, "the composed Interactable's interaction_radius is contact-sized (10.0)")
	_check(zone.interaction_radius < 16.0, "the composed Interactable's interaction_radius is smaller than Villager's default 16.0")

	var pc_combatant := Combatant.new()
	var companion := Combatant.new()
	var companions: Array = [companion]
	var bench_companion := Combatant.new()
	var bench: Array = [bench_companion]
	var party_inventory := PartyInventory.new()
	var vault := Vault.new()
	var fade_overlay := FadeOverlay.new()

	enemy.pc_combatant = pc_combatant
	enemy.companions = companions
	enemy.bench = bench
	enemy.party_inventory = party_inventory
	enemy.vault = vault
	enemy.fade_overlay = fade_overlay
	enemy.return_scene_path = "res://world/overworld_demo.tscn"
	enemy.pc_node = _pc_node

	enemy._begin_handoff()

	_check(combat_handoff.pc == pc_combatant, "triggering the composed Interactable sets CombatHandoff.pc")
	_check(combat_handoff.companions == companions, "CombatHandoff.companions is set")
	# Playtest-found bug (2026-07-12, fixed same session): begin_encounter() originally had no
	# bench param at all, so every real combat trigger silently reset CombatHandoff.bench to [].
	_check(combat_handoff.bench == bench, "CombatHandoff.bench is set (playtest-found bug, 2026-07-12: this used to silently reset to [])")
	_check(combat_handoff.party_inventory == party_inventory, "CombatHandoff.party_inventory is set")
	_check(combat_handoff.vault == vault, "CombatHandoff.vault is set")
	_check(combat_handoff.enemy_ids == [&"rat"], "CombatHandoff.enemy_ids carries the authored enemy_ids")
	_check(combat_handoff.pending_encounter_id == &"TestEnemy", "CombatHandoff.pending_encounter_id is the enemy node's name")
	_check(combat_handoff.return_scene_path == "res://world/overworld_demo.tscn", "CombatHandoff.return_scene_path is set")
	_check(combat_handoff.return_position == Vector2(321.0, 654.0), "CombatHandoff.return_position matches the PC node's global_position")
	_check(combat_handoff.has_return_position == true, "CombatHandoff.has_return_position is true")

	print(("OVERWORLD ENEMY TEST PASSED" if _failures == 0 else "OVERWORLD ENEMY TEST FAILED: %d" % _failures))
	quit(_failures)
	return true
