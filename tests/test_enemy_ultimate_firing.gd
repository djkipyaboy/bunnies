extends SceneTree

## Headless test: an enemy with a non-empty ultimate_id and an armed Bonus Meter fires its Ultimate
## (in preference to its base ability that turn) via the same _enemy_stage_ability()/_commit_main1()
## path every enemy ability already uses (spec 2026-07-19 §3.3) — the FIRST enemy-side Ultimate logic
## in this codebase. Also proves Dark Reinforcements' minion-summon effect.

var _instance: Combat
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
		var combat: Combat = _instance
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"
		pc.is_player = true
		pc.base_stats = Stats.new()
		pc.base_max_hp = 100
		pc.apply_stats()
		pc.start_combat()

		combat._pcs = [pc]
		combat._enemies = [boss]
		combat._dummies = []
		combat._turn_manager.combatants = [pc, boss]
		combat._panels[pc] = CombatantPanel.new()
		combat._panels[boss] = CombatantPanel.new()

		boss.bonus_meter.value = boss.bonus_meter.cap  # armed
		combat._attacker = boss
		combat._defender = pc
		boss.begin_turn()
		combat._plan = MainPhasePlan.new(boss, 0, 5, 2, null)
		combat._enemy_stage_ability()
		_check(combat._plan.fire_ultimate_staged, "an armed enemy Ultimate is staged by _enemy_stage_ability()")

		combat._commit_main1()
		_check(boss.bonus_meter.value == 0, "firing the Ultimate consumes the meter")
		_check(boss.boss_reinforcement_ids.size() == 2, "Dark Reinforcements summons 2 tracked reinforcements")
		for r: Combatant in boss.boss_reinforcement_ids:
			_check(r.max_hp == 30, "each Dark Reinforcements minion has 30 max HP (the lesser tier, got %d)" % r.max_hp)
			_check(combat._enemies.has(r), "each Dark Reinforcements minion is a real, targetable enemy Combatant")

		_check(combat._ultimate_label(&"dark_reinforcements") != "Fire Ultimate", "dark_reinforcements has a real button label, not the generic fallback")
		_check(combat._ultimate_name(&"dark_reinforcements") != "Ultimate", "dark_reinforcements has a real log name, not the generic fallback")

		_instance.free()
	if _frames >= 3:
		print(("ENEMY ULTIMATE FIRING TEST PASSED" if _failures == 0 else "ENEMY ULTIMATE FIRING TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
