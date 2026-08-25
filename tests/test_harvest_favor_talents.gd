extends SceneTree

# Headless test for the 3 Harvest's Favor row-5 talent upgrades (2026-08-24 harvester-talent-tree
# spec §8). Amplified Bond and Favor Unleashed are checked via direct harvest_favor_on_hit()/a new
# NEUTRAL-tier variant call; Spirit Surge via the new harvest_favor_spirit_surge_proc() method.
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_talents.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_harvester() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.level = Combatant.MAX_LEVEL
	return c

func _test_amplified_bond_scales_with_stage() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.pick_ability_talent(&"passive", &"harvest_favor_amplified_bond"), "picks harvest_favor_amplified_bond")
	var target1: Combatant = Combatant.new()
	target1.base_max_hp = 100; target1.apply_stats(); target1.start_combat()
	c.active_minion = MinionLibrary.make(false, &"ember")
	c.active_minion.minion_stage = 1
	c.harvest_favor_on_hit(target1, [c])
	var dmg_at_stage1: int = target1.max_hp - target1.hp

	var c2: Combatant = _mk_harvester()
	_check(c2.pick_ability_talent(&"passive", &"harvest_favor_amplified_bond"), "picks harvest_favor_amplified_bond (c2)")
	var target3: Combatant = Combatant.new()
	target3.base_max_hp = 100; target3.apply_stats(); target3.start_combat()
	c2.active_minion = MinionLibrary.make(false, &"ember")
	c2.active_minion.minion_stage = 3
	c2.harvest_favor_on_hit(target3, [c2])
	var dmg_at_stage3: int = target3.max_hp - target3.hp

	_check(dmg_at_stage3 > dmg_at_stage1, "harvest_favor_amplified_bond: stage-3 bonus (%d) exceeds stage-1 bonus (%d)" % [dmg_at_stage3, dmg_at_stage1])

func _test_favor_unleashed_triggers_on_neutral() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.pick_ability_talent(&"passive", &"harvest_favor_unleashed"), "picks harvest_favor_unleashed")
	c.active_minion = MinionLibrary.make(false, &"ember")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 100; target.apply_stats(); target.start_combat()
	c.harvest_favor_on_hit(target, [c], true)  # is_neutral = true
	_check(target.hp < target.max_hp, "harvest_favor_unleashed: a NEUTRAL-tier hit still triggers a (reduced) bonus")

func _test_favor_unleashed_required_for_neutral_trigger() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"ember")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 100; target.apply_stats(); target.start_combat()
	c.harvest_favor_on_hit(target, [c], true)
	_check(target.hp == target.max_hp, "without harvest_favor_unleashed: a NEUTRAL-tier hit does NOT trigger")

func _test_spirit_surge_guarantees_proc() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.pick_ability_talent(&"passive", &"harvest_favor_spirit_surge"), "picks harvest_favor_spirit_surge")
	c.active_minion = MinionLibrary.make(false, &"dew")
	var low_ally: Combatant = Combatant.new()
	low_ally.base_max_hp = 50; low_ally.apply_stats(); low_ally.start_combat(); low_ally.hp = 10
	c.harvest_favor_spirit_surge_proc([c, low_ally])
	_check(low_ally.hp > 10, "harvest_favor_spirit_surge: Upkeep proc healed the lowest-HP ally with no hit landed")

func _init() -> void:
	_test_amplified_bond_scales_with_stage()
	_test_favor_unleashed_triggers_on_neutral()
	_test_favor_unleashed_required_for_neutral_trigger()
	_test_spirit_surge_guarantees_proc()
	quit(_failures)
