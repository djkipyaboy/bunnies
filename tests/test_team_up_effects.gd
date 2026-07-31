extends SceneTree

# Headless test: TeamUpEffects.apply() — the Strike/Mend/Ward/Break/Surge resolution step
# (2026-07-29 spec §5). Pure Combatant-array logic, no full combat scene needed (mirrors how
# ClassLibrary/EnemyLibrary already build standalone Combatants for unit tests elsewhere).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_effects.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var light: DamageType = load("res://combat/resources/types/light.tres")

	var ally1: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var ally2: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	ally1.take_damage(ally1.max_hp - 10)
	ally2.take_damage(ally2.max_hp - 10)
	var enemy1: Combatant = EnemyLibrary.make(&"rat")
	var enemy2: Combatant = EnemyLibrary.make(&"ferret")
	var enemy1_hp_before: int = enemy1.hp
	var enemy2_hp_before: int = enemy2.hp

	var tally: Dictionary = {"strike": 2, "mend": 1, "ward": 1, "break": 3, "surge_lines": 0}
	TeamUpEffects.apply(tally, [ally1, ally2], [enemy1, enemy2], light)

	_check(enemy1.hp < enemy1_hp_before, "Strike damages enemy1 (%d -> %d)" % [enemy1_hp_before, enemy1.hp])
	_check(enemy2.hp < enemy2_hp_before, "Strike damages enemy2 (%d -> %d)" % [enemy2_hp_before, enemy2.hp])
	_check(ally1.hp == 10 + TeamUpEffects.MEND_PER_SYMBOL, "Mend heals ally1 by count(1)*MEND_PER_SYMBOL, no amplification (expected hp %d, got %d)" % [10 + TeamUpEffects.MEND_PER_SYMBOL, ally1.hp])
	_check(ally2.hp == 10 + TeamUpEffects.MEND_PER_SYMBOL, "Mend heals ally2 identically")
	_check(ally1.shield_hp == TeamUpEffects.WARD_PER_SYMBOL, "Ward shields ally1 by count(1)*WARD_PER_SYMBOL (got %d)" % ally1.shield_hp)
	_check(ally2.shield_hp == TeamUpEffects.WARD_PER_SYMBOL, "Ward shields ally2 identically")
	_check(enemy1.has_effect(&"weakened"), "Break applies the weakened debuff to enemy1")
	_check(enemy2.has_effect(&"weakened"), "Break applies the weakened debuff to enemy2")

	# --- Surge amplification stacks additively across completed lines ---
	var ally3: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	ally3.take_damage(ally3.max_hp - 10)
	var tally_surged: Dictionary = {"strike": 0, "mend": 1, "ward": 0, "break": 0, "surge_lines": 2}
	TeamUpEffects.apply(tally_surged, [ally3], [], light)
	var expected_amp: float = 1.0 + 2.0 * TeamUpEffects.SURGE_AMPLIFY_PER_LINE
	var expected_heal: int = ceili(1 * TeamUpEffects.MEND_PER_SYMBOL * expected_amp)
	_check(ally3.hp == 10 + expected_heal, "2 completed Surge lines amplify Mend (expected heal %d -> hp %d, got hp %d)" % [expected_heal, 10 + expected_heal, ally3.hp])

	# --- A Surge-only tally (no completed line) amplifies nothing on its own (spec §5: "a lone
	# locked Surge face... does nothing") ---
	var ally4: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	ally4.take_damage(ally4.max_hp - 10)
	TeamUpEffects.apply({"strike": 0, "mend": 1, "ward": 0, "break": 0, "surge_lines": 0}, [ally4], [], light)
	_check(ally4.hp == 10 + TeamUpEffects.MEND_PER_SYMBOL, "0 completed surge lines = no amplification (plain heal, got hp %d)" % ally4.hp)

	# --- An all-zero tally is a safe no-op ---
	var ally5: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var hp_before: int = ally5.hp
	TeamUpEffects.apply({"strike": 0, "mend": 0, "ward": 0, "break": 0, "surge_lines": 0}, [ally5], [], light)
	_check(ally5.hp == hp_before, "an all-zero tally is a safe no-op")
	_check(ally5.shield_hp == 0, "...and grants no shield")

	# --- A dead enemy is skipped (no crash, no effect on the already-dead) ---
	var enemy3: Combatant = EnemyLibrary.make(&"rat")
	enemy3.take_damage(9999)
	_check(not enemy3.is_alive(), "enemy3 is actually dead before this check")
	TeamUpEffects.apply({"strike": 5, "mend": 0, "ward": 0, "break": 5, "surge_lines": 0}, [], [enemy3], light)
	_check(not enemy3.has_effect(&"weakened"), "a dead enemy is skipped, not granted a debuff")

	print(("TEAM UP EFFECTS TEST PASSED" if _failures == 0 else "TEAM UP EFFECTS TEST FAILED: %d" % _failures))
	quit(_failures)
