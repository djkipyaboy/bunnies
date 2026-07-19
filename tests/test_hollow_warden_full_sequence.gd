extends SceneTree

## Full end-to-end integration test for The Hollow Warden (spec 2026-07-19) — proves the pieces built
## across Tasks 1-9 work TOGETHER in one real fight, not just in isolation.

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
		var combat: Combat = _instance as Combat
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		var healer: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_healer")
		var curser: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_curser")
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"; pc.is_player = true; pc.base_stats = Stats.new()
		pc.base_max_hp = 200; pc.apply_stats(); pc.start_combat()

		combat._pcs = [pc]
		combat._enemies = [boss, healer, curser]
		combat._dummies = []
		combat._turn_manager.combatants = [pc, boss, healer, curser]
		for c: Combatant in combat._turn_manager.combatants:
			combat._panels[c] = CombatantPanel.new()

		# 1. Phase-1 minions' scripted actions still work end-to-end via the real ability path.
		combat._attacker = healer
		combat._defender = pc
		boss.hp = 500
		healer.begin_turn()
		combat._plan = MainPhasePlan.new(healer, 0, 5, 2, null)
		combat._enemy_stage_ability()
		combat._commit_main1()
		_check(boss.hp == 530 or boss.hp == boss.max_hp, "the healer's scripted action heals the boss (capped at max)")
		_check(boss.has_effect(&"guarded"), "the healer's scripted action shields the boss")

		combat._attacker = curser
		curser.begin_turn()
		combat._plan = MainPhasePlan.new(curser, 0, 5, 2, null)
		combat._enemy_stage_ability()
		combat._commit_main1()
		_check(pc.has_effect(&"warden_curse"), "the curser's scripted action curses the PC")

		# 2. The 40% phase transition (calls the orchestrator method directly, same as Task 7's test —
		# _on_turn_started() itself is UI/timer-heavy and covered by human playtest, not headlessly).
		boss.hp = 200
		combat._attacker = boss
		boss.begin_turn()
		combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "the phase transition triggers for real below 40% HP")
		_check(boss.has_effect(&"indestructible"), "Indestructible is attached")

		# 3. Indestructible blocks a direct hit but not a DoT tick.
		var hp_before_hit: int = boss.hp
		boss.take_damage(int(boss.incoming_damage_multiplier() * 999))  # a "direct hit" scaled by the multiplier, mirroring how combat.gd computes final_damage
		_check(boss.hp == hp_before_hit, "Indestructible blocks a direct hit entirely")
		var curse_on_boss: Effect = EffectLibrary.make(&"warden_curse")
		curse_on_boss.dot_base_damage = 1.0
		boss.attach_effect(curse_on_boss)
		var dot_amount: int = ceili(curse_on_boss.dot_damage() * boss.dot_damage_multiplier())
		boss.take_damage(dot_amount)
		_check(boss.hp == hp_before_hit - dot_amount, "a DoT tick still damages the boss through Indestructible")

		# 4. Kill the phase-2 minions — Indestructible clears, Empowered applies.
		for m: Combatant in boss.boss_phase_minion_ids:
			m.take_damage(m.hp)
		combat._check_boss_phase_transition(boss)
		_check(not boss.has_effect(&"indestructible"), "Indestructible clears once phase-2 minions die")
		_check(boss.has_effect(&"empowered"), "Empowered applies once phase-2 minions die")

		# 5. The boss's Ultimate fires once its meter is full.
		boss.bonus_meter.value = boss.bonus_meter.cap
		combat._attacker = boss
		combat._defender = pc
		boss.begin_turn()
		combat._plan = MainPhasePlan.new(boss, 0, 5, 2, null)
		combat._enemy_stage_ability()
		combat._commit_main1()
		_check(boss.boss_reinforcement_ids.size() == 2, "Dark Reinforcements fires for real once the meter fills")

		_instance.free()
	if _frames >= 3:
		print(("HOLLOW WARDEN FULL SEQUENCE TEST PASSED" if _failures == 0 else "HOLLOW WARDEN FULL SEQUENCE TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
