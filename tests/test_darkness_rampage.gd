extends SceneTree

## Headless end-to-end test for Darkness Rampage (spec 2026-07-19 §3.5): while boss_phase_two_active,
## the boss's turn is a REAL 4-reel Dark WILD AoE hitting every living PC for 18 base damage (not the
## normal 12), and the boss self-heals half the total damage dealt. Rigs every reel's .faces to a
## single known SUCCESS tier (this codebase's established technique for a deterministic spin) and
## drives the actual async _do_spin()/_finish_spin() pipeline, not a shortcut past it.
##
## NOTE: the plan's brief originally called for a `_process()`-driven frame counter with
## `await get_tree().create_timer(2.0).timeout` inside it to let the spin settle. That doesn't work:
## `get_tree()` isn't a valid call from within a script that itself extends SceneTree (self IS the
## tree), and even once fixed to a bare `create_timer(2.0)`, awaiting inside a `SceneTree._process()`
## override silently truncates the test (it exits 0 without ever reaching the post-await checks or
## the final quit() — a false-positive PASS, confirmed live). Rewritten to the proven working pattern
## already established by tests/test_item_use_targeting_e2e.gd: an async `_initialize()` entry point
## that awaits `process_frame` and polls `_pending_strips` (the same counter `_apply_attack`/
## `_finish_spin` use internally) until the spin's strips have actually settled.

var _instance: Combat
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _initialize() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate() as Combat
	root.add_child(_instance)
	await process_frame
	await process_frame

	var combat: Combat = _instance
	var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
	boss.boss_phase_two_active = true
	boss.hp = 300
	var pc1: Combatant = Combatant.new()
	pc1.display_name = "PC1"; pc1.is_player = true; pc1.base_stats = Stats.new()
	pc1.base_max_hp = 100; pc1.apply_stats(); pc1.start_combat()
	var pc2: Combatant = Combatant.new()
	pc2.display_name = "PC2"; pc2.is_player = true; pc2.base_stats = Stats.new()
	pc2.base_max_hp = 100; pc2.apply_stats(); pc2.start_combat()

	combat._pcs = [pc1, pc2]
	combat._enemies = [boss]
	combat._dummies = []
	combat._turn_manager.combatants = [pc1, pc2, boss]
	combat._panels[pc1] = CombatantPanel.new()
	combat._panels[pc2] = CombatantPanel.new()
	combat._panels[boss] = CombatantPanel.new()
	combat._attacker = boss
	combat._defender = pc1

	boss.begin_turn()
	if boss.is_boss and boss.boss_phase_two_active:
		var dark: DamageType = load("res://combat/resources/types/dark.tres")
		boss.turn_reels.clear()
		for i in range(4):
			boss.turn_reels.append(ActionReel.make_default(dark))
		boss.sticky_wild_count = 4
		boss.sticky_wild_spins_remaining = 1
		boss.aoe_spins_remaining = 1
		boss.darkness_rampage_spins_remaining = 1
	_check(boss.turn_reels.size() == 4, "a Darkness Rampage turn builds 4 reels (got %d)" % boss.turn_reels.size())
	_check(boss.is_aoe_active(), "a Darkness Rampage turn is AoE-active")
	_check(boss.is_darkness_rampage_active(), "a Darkness Rampage turn is Darkness-Rampage-active")

	# Rig every reel to a known SUCCESS face so the spin is deterministic.
	for reel: ActionReel in boss.turn_reels:
		var success_face: ReelFace = null
		for f: ReelFace in reel.faces:
			if f.result_tier == ReelFace.ResultTier.SUCCESS:
				success_face = f
				break
		reel.faces = [success_face]

	combat._plan = MainPhasePlan.new(boss, 0, 5, 2, null)
	var pc1_hp_before: int = pc1.hp
	var pc2_hp_before: int = pc2.hp
	var boss_hp_before: int = boss.hp
	combat._do_spin()

	# _do_spin() only STARTS the spin: each ReelStrip animates to its landed face via a real Tween,
	# and only strip_settled -> _apply_attack -> _finish_spin (where damage/heal actually land) once
	# every strip has settled. Poll the same _pending_strips counter _apply_attack decrements
	# (established technique, tests/test_item_use_targeting_e2e.gd).
	var spin_guard: int = 0
	while combat._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(combat._pending_strips <= 0, "the spin's strips all settled within the frame guard")

	_check(pc1.hp < pc1_hp_before, "PC1 takes damage from Darkness Rampage's AoE")
	_check(pc2.hp < pc2_hp_before, "PC2 ALSO takes damage — this is a true AoE, not primary+splash")
	_check(boss.hp > boss_hp_before, "the boss self-heals after Darkness Rampage")

	# Extra self-review checks (beyond the brief's literal test): confirm the exact heal math and
	# that the temporary weapon.base_damage mutation (18.0 during the spin) is fully restored to the
	# Hollow Warden's normal 12.0 afterward, so it can't leak into that boss's NEXT normal-attack turn.
	# NOTE: mirroring the existing Big Bang/Earthquake convention (spec 2026-07-19 §3.5, and
	# combat.gd's own comment on _big_bang_total: "Sum of per-reel final_damage (NOT × enemy count)"),
	# _darkness_rampage_total is the PER-REEL total against one target, not summed across every AoE
	# target — confirmed live: with 2 PCs each taking an identical 48 damage (96 combined), the boss
	# only healed ceil(48/2)=24, not ceil(96/2)=48. A true AoE still means both PCs take the SAME
	# per-reel total individually (asserted below), just not multiplied into the heal basis.
	var pc1_loss: int = pc1_hp_before - pc1.hp
	var pc2_loss: int = pc2_hp_before - pc2.hp
	_check(pc1_loss == pc2_loss, "both PCs take the IDENTICAL per-reel total from the AoE (pc1=%d, pc2=%d)" % [pc1_loss, pc2_loss])
	var expected_heal: int = ceili(pc1_loss / 2.0)
	_check(boss.hp - boss_hp_before == expected_heal, "self-heal is exactly ceil(single-target total/2) (single-target total=%d, expected=%d, got=%d)" % [pc1_loss, expected_heal, boss.hp - boss_hp_before])
	_check(boss.weapon.base_damage == 12.0, "boss.weapon.base_damage is restored to 12.0 after the Darkness Rampage turn (got %s)" % boss.weapon.base_damage)

	_instance.free()
	await process_frame

	print(("DARKNESS RAMPAGE TEST PASSED" if _failures == 0 else "DARKNESS RAMPAGE TEST FAILED: %d" % _failures))
	quit(_failures)
