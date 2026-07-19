extends SceneTree

## Headless test for Combat._spawn_enemy_mid_combat() (spec 2026-07-19 §3.6) — the one genuinely new
## piece of plumbing this boss fight needs: a Combatant spawned AFTER _build_combatants() has already
## run must be fully playable in the SAME round it appears — targetable, panel-visible, and takes its
## own turn before the round ends — not merely present in a data array.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Node = _instance
		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"
		pc.is_player = true
		pc.base_stats = Stats.new()
		pc.base_max_hp = 100
		pc.apply_stats()
		pc.start_combat()
		var rat: Combatant = EnemyLibrary.make(&"rat")

		combat._pcs = [pc] as Array[Combatant]
		combat._enemies = [rat] as Array[Combatant]
		combat._dummies = [] as Array[Combatant]
		combat._turn_manager.combatants = [pc, rat] as Array[Combatant]
		combat._pc = pc
		combat._enemy = rat
		combat._panels[pc] = CombatantPanel.new()
		combat._panels[rat] = CombatantPanel.new()
		combat._turn_manager.begin()

		var before_enemies: int = combat._enemies.size()
		var before_combatants: int = combat._turn_manager.combatants.size()
		var spawned: Combatant = combat._spawn_enemy_mid_combat(&"warden_acolyte_lesser_healer")

		_check(spawned != null, "_spawn_enemy_mid_combat returns a real Combatant")
		_check(combat._enemies.size() == before_enemies + 1, "the spawned Combatant is appended to _enemies")
		_check(combat._turn_manager.combatants.size() == before_combatants + 1, "the spawned Combatant is appended to TurnManager.combatants")
		_check(combat._panels.has(spawned), "the spawned Combatant has a real CombatantPanel registered")
		_check(combat._enemies_of(pc).has(spawned), "the spawned Combatant is targetable via _enemies_of() from the PC's side")

		# Behavioral contract: it must act THIS round, not just next round.
		# Canonical drain pattern (tests/test_acts_last_turn_order.gd): seed `seen` with the combatant
		# already active (begin() already announced index 0 before the spawn), then call advance_turn()
		# exactly N-1 times for N acting combatants this round (pc, rat, spawned = 3, so 2 calls) — a
		# 3rd call would be the one that wraps past the end and rolls a new round.
		var round_before: int = combat._turn_manager.round_number
		var seen: Array[Combatant] = [combat._turn_manager._order[combat._turn_manager._turn_index]]
		for i in range(2):
			combat._turn_manager.advance_turn()
			seen.append(combat._turn_manager._order[combat._turn_manager._turn_index])
		_check(spawned in seen, "the spawned Combatant takes a turn in the SAME round it was spawned")
		_check(combat._turn_manager.round_number == round_before, "no new round started while draining the round's remaining turns")

		# Not connected to the XP/Amber reward hookup (spec 2026-07-19 §3.3 sacrifice rule).
		var xp_before: int = pc.xp
		spawned.take_damage(spawned.hp)
		_check(pc.xp == xp_before, "defeating a mid-combat-spawned Combatant grants NO XP (no _on_enemy_defeated connection)")

		_instance.free()
	if _frames >= 3:
		quit()
		return true
	return false
