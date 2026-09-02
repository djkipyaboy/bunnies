extends SceneTree

# Headless test: Harvest's Favor passive amplification at level 9
# (2026-09-02 harvester-rank2-content spec §3). harvest_favor_on_hit() is a pure Combatant method
# (no Combat/scene dependency), so this test builds bare Combatants directly.
#
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_rank2.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a Harvester with an active minion of [param minion_type] at [param level], Focus zeroed
## (isolates rank-up from stat scaling — tested separately).
func _harvester(level: int, minion_type: StringName) -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.level = level
	c.base_stats.focus = 0
	c.active_minion = MinionLibrary.make(false, minion_type)
	return c

func _run_rank1_regression() -> void:
	var caster: Combatant = _harvester(8, &"ember")
	var target: Combatant = EnemyLibrary.make(&"rat")
	var hp_before: int = target.hp
	caster.harvest_favor_on_hit(target, [caster])
	_check(target.hp == hp_before - 4, "level 8: rank-1 Ember bonus damage 4 unchanged (hp %d -> %d)" % [hp_before, target.hp])

	var dew_caster: Combatant = _harvester(8, &"dew")
	dew_caster.take_damage(30)
	var hp_before_heal: int = dew_caster.hp
	dew_caster.harvest_favor_on_hit(null, [dew_caster])
	_check(dew_caster.hp == hp_before_heal + 3, "level 8: rank-1 Dew heal 3 unchanged (hp %d -> %d)" % [hp_before_heal, dew_caster.hp])

func _run_amplified_values() -> void:
	var caster: Combatant = _harvester(9, &"ember")
	var target: Combatant = EnemyLibrary.make(&"rat")
	var hp_before: int = target.hp
	caster.harvest_favor_on_hit(target, [caster])
	_check(target.hp == hp_before - 8, "level 9: amplified Ember bonus damage 8 (hp %d -> %d)" % [hp_before, target.hp])

	var dew_caster: Combatant = _harvester(9, &"dew")
	dew_caster.take_damage(30)
	var hp_before_heal: int = dew_caster.hp
	dew_caster.harvest_favor_on_hit(null, [dew_caster])
	_check(dew_caster.hp == hp_before_heal + 6, "level 9: amplified Dew heal 6 (hp %d -> %d)" % [hp_before_heal, dew_caster.hp])

	var misfortune_caster: Combatant = _harvester(9, &"misfortune")
	var enemy: Combatant = EnemyLibrary.make(&"rat")
	var weak: Effect = EffectLibrary.make(&"weakened")
	weak.duration = 2
	enemy.attach_effect(weak)
	misfortune_caster.harvest_favor_on_hit(enemy, [misfortune_caster])
	_check(enemy._find_effect(&"weakened").duration == 4, "level 9: amplified Misfortune duration extension +2 turns (got %d)" % enemy._find_effect(&"weakened").duration)

func _run_amplified_stat_scaling() -> void:
	var caster: Combatant = _harvester(9, &"ember")
	caster.base_stats.focus = 4
	var target: Combatant = EnemyLibrary.make(&"rat")
	var hp_before: int = target.hp
	caster.harvest_favor_on_hit(target, [caster])
	var expected: int = ceili(8 * 1.5)
	_check(target.hp == hp_before - expected, "level 9, Focus 4: amplified Ember damage (8) scaled by 1.5 -> %d (hp %d -> %d)" % [expected, hp_before, target.hp])

func _initialize() -> void:
	_run_rank1_regression()
	_run_amplified_values()
	_run_amplified_stat_scaling()
	print(("HARVEST FAVOR RANK-2 TEST PASSED" if _failures == 0 else "HARVEST FAVOR RANK-2 TEST FAILED: %d" % _failures))
	quit(_failures)
