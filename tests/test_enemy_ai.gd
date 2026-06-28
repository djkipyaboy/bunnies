extends SceneTree

# Headless test: EnemyAI.pick_target — first-iteration enemy targeting (spec 2026-06-28 §3.1).
# Pure/static; we hand-build minimal DamageType + Combatant objects (no scene).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_ai.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

# Build a DamageType whose row gives `mult` against PIERCING (the defenders' def type),
# and 1.0 against everything else.
func _atk(mult_vs_def: float) -> DamageType:
	var dt := DamageType.new()
	dt.type = DamageType.Type.SLASHING
	dt.default_multiplier = 1.0
	dt.effectiveness = {DamageType.Type.PIERCING: mult_vs_def}
	return dt

func _def() -> DamageType:
	var dt := DamageType.new()
	dt.type = DamageType.Type.PIERCING
	return dt

# Minimal PC: alive, given hp + defense_type (PIERCING).
func _pc(hp: int) -> Combatant:
	var c := Combatant.new()
	c.is_player = true
	c.defense_type = _def()
	c.base_max_hp = 1000
	c.apply_stats()
	c.start_combat()
	c.hp = hp
	return c

# Minimal attacker: a Weapon of one reel typed `atk` so weapon_type() returns it.
func _enemy(atk: DamageType) -> Combatant:
	var c := Combatant.new()
	c.is_player = false
	var w := Weapon.new()
	w.base_damage = 5.0
	w.reels.append(ActionReel.make_default(atk))
	c.weapon = w
	return c

func _initialize() -> void:
	# No living PCs -> null.
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), []) == null, "empty -> null")

	# Super-effective beats neutral even when the neutral target is lower HP.
	var super_eff := _pc(900)     # def PIERCING; attacker 1.25 vs PIERCING -> super-effective
	var neutral2 := Combatant.new(); neutral2.is_player = true
	neutral2.defense_type = DamageType.new(); (neutral2.defense_type as DamageType).type = DamageType.Type.EARTH
	neutral2.base_max_hp = 1000; neutral2.apply_stats(); neutral2.start_combat(); neutral2.hp = 100
	var atk125 := _atk(1.25)  # 1.25 vs PIERCING, 1.0 vs EARTH (default)
	_check(EnemyAI.pick_target(_enemy(atk125), [neutral2, super_eff]) == super_eff,
		"super-effective chosen over lower-HP neutral")

	# Within the same tier, lowest HP wins.
	var a := _pc(500)
	var b := _pc(200)
	var c := _pc(800)
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), [a, b, c]) == b, "neutral tier -> lowest HP (b)")

	# HP tie within a tier -> first in order.
	var d := _pc(300)
	var e := _pc(300)
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), [d, e]) == d, "HP tie -> first in order")

	# All resisted -> still attacks the lowest-HP of them (no passing the turn).
	var r1 := _pc(400)
	var r2 := _pc(150)
	_check(EnemyAI.pick_target(_enemy(_atk(0.75)), [r1, r2]) == r2, "all-resisted fallback -> lowest HP")

	# Dead PCs are skipped.
	var dead := _pc(500); dead.hp = 0
	var live := _pc(600)
	_check(EnemyAI.pick_target(_enemy(_atk(1.0)), [dead, live]) == live, "dead PC skipped")

	print(("ENEMY AI TEST PASSED" if _failures == 0 else "ENEMY AI TEST FAILED: %d" % _failures))
	quit(_failures)
