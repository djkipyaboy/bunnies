extends SceneTree

## Headless test: Combatant.clear_combat_effects() wipes ALL active effects (buff + debuff) and any
## residual shield, and _on_combat_ended() calls it for every _pcs member — player decision
## 2026-07-31: combat effects must NOT survive from one fight into a separate later encounter,
## since CombatHandoff reuses the same real Combatant instances across sequential fights.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_clear_combat_effects_on_combat_end.gd

var _instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# --- Combatant.clear_combat_effects() itself ---
		var solo: Combatant = Combatant.new()
		solo.base_stats = Stats.new(); solo.base_max_hp = 100; solo.apply_stats(); solo.start_combat()
		solo.attach_effect(EffectLibrary.make(&"guarded"))
		solo.attach_effect(EffectLibrary.make(&"taunt"))
		solo.apply_shield(20, 2)
		solo.clear_combat_effects()
		_check(solo.active_effects.is_empty(), "clear_combat_effects wipes every effect, including beneficial ones cleanse() would keep")
		_check(solo.shield_hp == 0 and solo.shield_turns == 0, "clear_combat_effects also zeroes any residual shield (got %d/%d)" % [solo.shield_hp, solo.shield_turns])

		# --- wired into _on_combat_ended() for every _pcs member ---
		var combat: Combat = _instance as Combat
		var pc1: Combatant = Combatant.new()
		pc1.display_name = "PC1"; pc1.is_player = true
		pc1.base_stats = Stats.new(); pc1.base_max_hp = 100; pc1.apply_stats(); pc1.start_combat()
		pc1.attach_effect(EffectLibrary.make(&"guarded"))
		var pc2: Combatant = Combatant.new()
		pc2.display_name = "PC2 (companion)"; pc2.is_player = true
		pc2.base_stats = Stats.new(); pc2.base_max_hp = 100; pc2.apply_stats(); pc2.start_combat()
		pc2.attach_effect(EffectLibrary.make(&"taunt"))
		combat._pcs = [pc1, pc2]
		combat._enemies = []
		combat._arrived_via_handoff = false

		combat._on_combat_ended(true)
		_check(pc1.active_effects.is_empty(), "PC1's effects are cleared when combat ends")
		_check(pc2.active_effects.is_empty(), "PC2's (companion's) effects are cleared too")

		print(("CLEAR COMBAT EFFECTS ON COMBAT END TEST PASSED" if _failures == 0 else "CLEAR COMBAT EFFECTS ON COMBAT END TEST FAILED: %d" % _failures))
		quit(_failures)
	return false
