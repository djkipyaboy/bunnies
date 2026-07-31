extends SceneTree

## Headless test: Basil's (Skirmisher) Riposte Storm charge count must be visible on the panel —
## playtest 2026-07-31 found riposte_charges had NO UI display anywhere.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_riposte_charge_counter.gd

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
		# --- CombatantPanel-level: refresh_riposte() renders the count, blank at 0 ---
		var c: Combatant = Combatant.new()
		c.base_stats = Stats.new(); c.base_max_hp = 100; c.apply_stats(); c.start_combat()
		var panel: CombatantPanel = CombatantPanel.new()
		root.add_child(panel)
		panel.bind(c)
		_check(panel._riposte_label.text == "", "blank at 0 charges right after bind()")
		c.gain_riposte_charges(3)
		panel.refresh_riposte()
		_check(panel._riposte_label.text.contains("3"), "shows the charge count once gained (got '%s')" % panel._riposte_label.text)

		# --- combat.gd wiring: gaining a charge on the defender's panel refreshes it live ---
		var combat: Combat = _instance as Combat
		var defender: Combatant = Combatant.new()
		defender.base_stats = Stats.new(); defender.base_max_hp = 100; defender.apply_stats(); defender.start_combat()
		defender.attach_effect(EffectLibrary.make(&"evasion"))
		var attacker: Combatant = Combatant.new()
		attacker.is_player = false
		var w: Weapon = Weapon.new(); w.base_damage = 5.0
		w.reels.append(ActionReel.make_default(null))
		attacker.weapon = w
		attacker.turn_reels = [w.reels[0]]
		combat._attacker = attacker
		combat._defender = defender
		combat._panels[defender] = CombatantPanel.new()
		root.add_child(combat._panels[defender])
		combat._panels[defender].bind(defender)

		defender.gain_riposte_charges(1)
		(combat._panels[defender] as CombatantPanel).refresh_riposte()
		_check((combat._panels[defender] as CombatantPanel)._riposte_label.text.contains("1"), "the defender's panel shows the gained charge")

		print(("RIPOSTE CHARGE COUNTER TEST PASSED" if _failures == 0 else "RIPOSTE CHARGE COUNTER TEST FAILED: %d" % _failures))
		quit(_failures)
	return false
