extends SceneTree

## Headless test for the boss phase-transition orchestrator (spec 2026-07-19 §3.3): the 40%-HP
## trigger, Indestructible attach + 2 new 60-HP minions (playtest 2026-07-19, down from 90),
## Indestructible clearing once both die,
## Empowered applying afterward, the 10-turn-of-the-BOSS'S-OWN-turns cooldown gating a re-trigger,
## Indestructible always superseding Empowered (never both active), and reinforcements being
## sacrificed (boss heals half their HP, no reward) if still alive at a later trigger.

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
		var combat: Node = _instance
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		combat._panels[boss] = CombatantPanel.new()
		combat._turn_manager.combatants = [boss] as Array[Combatant]
		combat._enemies = [boss] as Array[Combatant]
		combat._dummies = [] as Array[Combatant]

		# Not yet below 40% (550 * 0.4 = 220) — no trigger.
		boss.hp = 230
		combat._check_boss_phase_transition(boss)
		_check(not boss.boss_phase_two_active, "no trigger above the 40% threshold")
		_check(boss.boss_turns_taken == 1, "boss_turns_taken increments every check")

		# Drop below 40% — triggers.
		boss.hp = 200
		combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "the transition triggers once HP drops below 220 (40%)")
		_check(boss.has_effect(&"indestructible"), "the boss gains Indestructible")
		_check(boss.boss_phase_minion_ids.size() == 2, "2 new minions are tracked as this phase's minions")
		for m: Combatant in boss.boss_phase_minion_ids:
			_check(m.max_hp == 60, "each phase-2 minion has 60 max HP (playtest 2026-07-19, down from 90; got %d)" % m.max_hp)
			_check(combat._enemies.has(m), "each phase-2 minion is a real, targetable enemy Combatant")

		# Doesn't re-trigger the same turn it just resolved (both minions still alive).
		combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "still in phase 2 while both minions live")
		_check(boss.boss_phase_minion_ids.size() == 2, "no second pair spawned while still in phase 2")

		# Kill both phase-2 minions — Indestructible clears, Empowered applies.
		for m: Combatant in boss.boss_phase_minion_ids:
			m.take_damage(m.hp)
		combat._check_boss_phase_transition(boss)
		_check(not boss.boss_phase_two_active, "phase 2 ends once both minions are dead")
		_check(not boss.has_effect(&"indestructible"), "Indestructible clears when phase 2 ends")
		_check(boss.has_effect(&"empowered"), "Empowered applies once phase 2 ends")

		# Still below 40% but cooldown hasn't elapsed (boss_turns_taken is only 4 so far) — no re-trigger.
		combat._check_boss_phase_transition(boss)
		_check(not boss.boss_phase_two_active, "no re-trigger before the 10-turn cooldown elapses")
		_check(boss.has_effect(&"empowered"), "Empowered persists while waiting on cooldown")

		# Fast-forward the boss's own turns to elapse the cooldown.
		for i in range(10):
			combat._check_boss_phase_transition(boss)
		_check(boss.boss_phase_two_active, "the transition re-triggers once 10 of the boss's own turns have passed below threshold")
		_check(not boss.has_effect(&"empowered"), "Empowered is removed the instant Indestructible re-triggers — they never both apply")
		_check(boss.has_effect(&"indestructible"), "Indestructible is active again on the re-trigger")

		# Sacrifice check: summon 2 reinforcements, then trigger another cycle while they're still alive.
		for m: Combatant in boss.boss_phase_minion_ids:
			m.take_damage(m.hp)
		combat._check_boss_phase_transition(boss)  # clears phase 2, applies Empowered again
		var r1: Combatant = combat._spawn_enemy_mid_combat(&"warden_acolyte_lesser_healer")
		var r2: Combatant = combat._spawn_enemy_mid_combat(&"warden_acolyte_lesser_curser")
		boss.boss_reinforcement_ids = [r1, r2]
		var reinforcement_hp_total: int = r1.hp + r2.hp
		var boss_hp_before_sacrifice: int = boss.hp
		for i in range(10):
			combat._check_boss_phase_transition(boss)  # elapse cooldown again
		_check(boss.boss_phase_two_active, "the transition re-triggers a second time")
		_check(not r1.is_alive() and not r2.is_alive(), "surviving reinforcements are sacrificed on the next trigger")
		var expected_heal: int = ceili(reinforcement_hp_total / 2.0)
		_check(boss.hp == mini(boss_hp_before_sacrifice + expected_heal, boss.max_hp), "the boss heals half the sacrificed reinforcements' combined HP")

		_instance.free()
	if _frames >= 3:
		print(("BOSS PHASE TRANSITION TEST PASSED" if _failures == 0 else "BOSS PHASE TRANSITION TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
