extends SceneTree

# Headless test for the Harvest's Favor passive base behavior (2026-08-24 harvester-talent-tree
# spec §1) — no minion active = no-op; each minion type's on-hit bonus fires from a direct
# harvest_favor_on_hit() call (mirrors this codebase's precedent of unit-testing a Combatant-level
# hook directly rather than driving a full spin — see tests/test_ability_talents_warrior.gd's header
# comment on Bleeding Wild for the same rationale).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_harvest_favor_passive.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_harvester() -> Combatant:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.level = Combatant.MAX_LEVEL
	return c

func _init() -> void:
	_test_passive_id_set()
	_test_no_minion_no_effect()
	_test_ember_active_deals_bonus_damage()
	_test_dew_active_heals_lowest_hp_ally()
	_test_misfortune_active_extends_debuff()
	_test_hasty_active_extends_own_buff()
	quit(_failures)

func _test_passive_id_set() -> void:
	var c: Combatant = _mk_harvester()
	_check(c.passive_ability_id == &"harvest_favor", "Harvester's passive_ability_id is harvest_favor")

func _test_no_minion_no_effect() -> void:
	var c: Combatant = _mk_harvester()
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	var hp_before: int = target.hp
	c.harvest_favor_on_hit(target, [c])
	_check(target.hp == hp_before, "no active minion: harvest_favor_on_hit is a no-op")

func _test_ember_active_deals_bonus_damage() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"ember")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	var hp_before: int = target.hp
	c.harvest_favor_on_hit(target, [c])
	_check(target.hp < hp_before, "Touch-Me-Not active: harvest_favor_on_hit dealt bonus damage to the target")

func _test_dew_active_heals_lowest_hp_ally() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"dew")
	var low_ally: Combatant = Combatant.new()
	low_ally.base_max_hp = 50; low_ally.apply_stats(); low_ally.start_combat(); low_ally.hp = 10
	var high_ally: Combatant = Combatant.new()
	high_ally.base_max_hp = 50; high_ally.apply_stats(); high_ally.start_combat(); high_ally.hp = 45
	var enemy: Combatant = Combatant.new()
	enemy.base_max_hp = 50; enemy.apply_stats(); enemy.start_combat()
	c.harvest_favor_on_hit(enemy, [c, low_ally, high_ally])
	_check(low_ally.hp > 10, "Lotus active: harvest_favor_on_hit healed the lowest-HP ally (got %d)" % low_ally.hp)
	_check(high_ally.hp == 45, "Lotus active: harvest_favor_on_hit left the higher-HP ally untouched")

func _test_misfortune_active_extends_debuff() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"misfortune")
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	var weakened: Effect = EffectLibrary.make(&"weakened")
	weakened.duration = 1
	target.attach_effect(weakened)
	c.harvest_favor_on_hit(target, [c])
	var found: Effect = target._find_effect(&"weakened")
	_check(found != null and found.duration == 2, "Nightshade active: extended the target's Weakened duration by 1 (got %d)" % (found.duration if found != null else -1))

func _test_hasty_active_extends_own_buff() -> void:
	var c: Combatant = _mk_harvester()
	c.active_minion = MinionLibrary.make(false, &"hasty")
	var haste: Effect = EffectLibrary.make(&"empowered")
	haste.duration = 1
	c.attach_effect(haste)
	var target: Combatant = Combatant.new()
	target.base_max_hp = 50; target.apply_stats(); target.start_combat()
	c.harvest_favor_on_hit(target, [c])
	var found: Effect = c._find_effect(&"empowered")
	_check(found != null and found.duration == 2, "Wheat active: extended the HARVESTER'S OWN buff duration by 1 (got %d)" % (found.duration if found != null else -1))
