extends SceneTree

## Headless test for the Warden Acolytes' 2 ability roles (spec 2026-07-19 §3.2): warden_support_heal
## (heal the boss ally 30 HP + attach Guarded) and warden_support_curse (attach a flat warden_curse
## DoT to every living PC). Drives combat.gd's real _enemy_stage_ability()/_commit_main1() path
## directly rather than a full scripted spin, mirroring this codebase's existing precedent for
## testing orchestrator-applied pending-flag abilities (Foresight/Regrowth).

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
		boss.hp = 400  # damaged, so the heal is visible against a non-max HP
		var healer: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_healer")
		var curser: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_curser")
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"
		pc.is_player = true
		pc.base_stats = Stats.new()
		pc.base_max_hp = 100
		pc.apply_stats()
		pc.start_combat()

		combat._pcs = [pc]
		combat._enemies = [boss, healer, curser]
		combat._turn_manager.combatants = [pc, boss, healer, curser]
		combat._panels[boss] = CombatantPanel.new()
		combat._panels[healer] = CombatantPanel.new()
		combat._panels[curser] = CombatantPanel.new()
		combat._panels[pc] = CombatantPanel.new()

		# Healer's turn: stage + commit its ability directly.
		combat._attacker = healer
		combat._defender = pc
		healer.begin_turn()
		combat._plan = MainPhasePlan.new(healer, 0, 5, 2, null)
		combat._enemy_stage_ability()
		_check(combat._plan.ability_staged, "warden_support_heal is always-staged (greedy AI)")
		combat._commit_main1()
		_check(boss.hp == 430, "the boss heals 30 HP from warden_support_heal (400 -> 430, got %d)" % boss.hp)
		_check(boss.has_effect(&"guarded"), "warden_support_heal attaches Guarded to the boss")

		# Curser's turn: stage + commit its ability directly.
		combat._attacker = curser
		combat._defender = pc
		curser.begin_turn()
		combat._plan = MainPhasePlan.new(curser, 0, 5, 2, null)
		combat._enemy_stage_ability()
		_check(combat._plan.ability_staged, "warden_support_curse is always-staged (greedy AI)")
		combat._commit_main1()
		_check(pc.has_effect(&"warden_curse"), "warden_support_curse attaches warden_curse to the living PC")
		var curse: Effect = pc._find_effect(&"warden_curse")
		_check(curse.dot_damage() == 4, "the applied warden_curse deals the flat 4 (1 stack), not a weapon-scaled number (got %d)" % curse.dot_damage())

		_instance.free()
	if _frames >= 3:
		print(("WARDEN ACOLYTE ABILITIES TEST PASSED" if _failures == 0 else "WARDEN ACOLYTE ABILITIES TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
