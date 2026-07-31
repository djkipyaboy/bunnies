extends SceneTree

## Headless test: payline crit-line bonus damage and _splash_half_to_others() must respect the
## SAME outgoing/incoming damage-multiplier math normal reel attacks already use (Indestructible,
## Guarded, etc.) — playtest 2026-07-31 found both paths calling take_damage() with a raw,
## unmitigated amount.
## Run: Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_payline_and_splash_damage_multiplier.gd

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

func _make_armed_attacker(type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = "TestAttacker"
	c.is_player = true
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.base_stats = Stats.new()
	c.base_max_hp = 200
	c.apply_stats()
	c.start_combat()
	return c

func _make_target(is_player_side: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = "TestTarget"
	c.is_player = is_player_side
	c.base_stats = Stats.new()
	c.base_max_hp = 300
	c.apply_stats()
	c.start_combat()
	return c

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Combat = _instance as Combat
		var crushing: DamageType = load("res://combat/resources/types/crushing.tres")

		# --- CRIT LINE bonus damage must respect the defender's incoming multiplier ---
		var attacker: Combatant = _make_armed_attacker(crushing)
		var defender: Combatant = _make_target(false)
		defender.attach_effect(EffectLibrary.make(&"indestructible"))
		combat._attacker = attacker
		combat._defender = defender
		combat._panels[attacker] = CombatantPanel.new()
		combat._panels[defender] = CombatantPanel.new()

		var hit := PaylineResolver.PaylineHit.new()
		hit.tier = ReelFace.ResultTier.CRIT_SUCCESS
		hit.length = 3
		hit.cells = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
		var hp_before: int = defender.hp
		combat._on_paylines_resolved([hit])
		_check(defender.hp == hp_before, "Indestructible blocks the CRIT LINE bonus entirely (dealt %d)" % (hp_before - defender.hp))

		defender.remove_effect(&"indestructible")
		hp_before = defender.hp
		combat._on_paylines_resolved([hit])
		_check(defender.hp < hp_before, "the CRIT LINE bonus still deals real damage once Indestructible is gone")

		# --- _splash_half_to_others() must apply each OTHER target's OWN incoming multiplier ---
		var splasher: Combatant = _make_armed_attacker(crushing)
		var primary: Combatant = _make_target(false)
		var guarded_enemy: Combatant = _make_target(false)
		guarded_enemy.attach_effect(EffectLibrary.make(&"guarded"))
		var plain_enemy: Combatant = _make_target(false)
		combat._attacker = splasher
		combat._defender = primary
		combat._turn_manager.combatants = [splasher, primary, guarded_enemy, plain_enemy]
		combat._panels[guarded_enemy] = CombatantPanel.new()
		combat._panels[plain_enemy] = CombatantPanel.new()

		var guarded_hp_before: int = guarded_enemy.hp
		var plain_hp_before: int = plain_enemy.hp
		combat._splash_half_to_others(splasher, 40, "Crushing")
		var guarded_dmg: int = guarded_hp_before - guarded_enemy.hp
		var plain_dmg: int = plain_hp_before - plain_enemy.hp
		_check(guarded_dmg > 0 and plain_dmg > 0, "both targets took some splash damage")
		_check(guarded_dmg < plain_dmg, "Guarded's 0.75 incoming multiplier reduces its splash vs. the plain target (guarded=%d plain=%d)" % [guarded_dmg, plain_dmg])
		_check(guarded_dmg == ceili(ceili(40 * 0.5) * 0.75), "Guarded splash matches ceil(ceil(40*0.5) * 0.75) exactly (got %d)" % guarded_dmg)

		print(("PAYLINE/SPLASH DAMAGE MULTIPLIER TEST PASSED" if _failures == 0 else "PAYLINE/SPLASH DAMAGE MULTIPLIER TEST FAILED: %d" % _failures))
		quit(_failures)
	return false
