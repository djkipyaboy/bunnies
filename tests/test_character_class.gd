extends SceneTree

# Headless test: CharacterClass.build_combatant() stamps a Combatant with stat-derived state.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_character_class.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var cc: CharacterClass = CharacterClass.new()
	cc.display_name = "Test Warrior"
	cc.species = "Mouse"
	var s: Stats = Stats.new(); s.might = 3; s.vigor = 3; s.focus = 1; s.grit = 2; s.luck = 3
	cc.base_stats = s
	cc.weapon_base_damage = 8.0
	cc.weapon_type = slashing
	cc.reel_count = 3
	cc.defense_type = slashing
	cc.base_max_hp = 100
	cc.base_max_stamina = 5
	cc.base_meter_floor = 3
	cc.meter_cap = 15
	cc.ability_id = &"rend"
	cc.start_stamina = 3
	cc.stamina_regen = 1
	cc.weapon_display_name = "Test Sword"

	var c: Combatant = cc.build_combatant(true)
	_check(c.display_name == "Test Warrior", "display_name copied")
	_check(c.is_player == true, "is_player set")
	_check(c.weapon != null and c.weapon.reels.size() == 3, "weapon has reel_count=3 reels (got %d)" % (c.weapon.reels.size() if c.weapon else -1))
	_check(c.weapon.base_damage == 8.0, "weapon base_damage copied")
	_check(c.weapon.display_name == "Test Sword", "weapon.display_name copied from weapon_display_name (player-reported gap, 2026-07-12: this used to be left blank, reading as 'no weapon equipped' in the inventory UI)")
	_check(c.defense_type == slashing, "defense_type set")
	_check(c.ability_id == &"rend", "ability_id set")
	# Derived: max_hp = base 100 + vigor 3 = 103; max_stamina = base 5 + focus 1 = 6; floor = 3 + grit 2 = 5.
	_check(c.max_hp == 103, "max_hp = 100 + vigor 3 = 103 (got %d)" % c.max_hp)
	_check(c.resource_pool != null and c.resource_pool.max_stamina == 6, "max_stamina = 5 + focus 1 = 6 (got %d)" % (c.resource_pool.max_stamina if c.resource_pool else -1))
	_check(c.bonus_meter != null and c.bonus_meter.floor == 5, "meter floor = 3 + grit 2 = 5 (got %d)" % (c.bonus_meter.floor if c.bonus_meter else -1))
	_check(c.bonus_meter.cap == 15, "meter cap copied")
	_check(c.hp == c.max_hp, "start_combat seeded full HP")
	# Luck 3 -> floor(3/3) = 1 crit-failure face converted to crit-success per reel (REPLACE
	# mechanic, 2026-08-13 accuracy-stat spec §2). DEFAULT_COMPOSITION now has 5 native crit-success
	# faces (5x scale) + 1 converted = 6.
	var crit: int = 0
	for f: ReelFace in c.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
	_check(crit == 6, "apply_luck converted floor(3/3)=1 crit-failure face to crit-success (5 native + 1 = 6; got %d)" % crit)

	# Enemy build: no meter visibility, no stamina pool.
	var ec: CharacterClass = CharacterClass.new()
	ec.weapon_type = slashing; ec.defense_type = slashing; ec.reel_count = 2
	var e: Combatant = ec.build_combatant(false)
	_check(e.bonus_meter != null and e.bonus_meter.is_visible == false, "enemy meter hidden")
	_check(e.resource_pool == null, "enemy has no stamina pool")

	# Regression (player-reported, 2026-07-12): every real ClassLibrary class must name its starting
	# weapon — a blank name reads as "nothing equipped" in the paperdoll even though it's a real,
	# fully-functional weapon.
	for id: StringName in ClassLibrary.IDS:
		var built: Combatant = ClassLibrary.make(id).build_combatant(true)
		_check(not built.weapon.display_name.is_empty(), "%s's starting weapon has a display_name" % id)

	# power_stat is copied from resolve_power_stat() at build time (design spec 2026-08-28 §2.1/§3),
	# and its live value reads correctly off effective_stats().
	var pc: CharacterClass = CharacterClass.new()
	pc.combat_role = &"caster"
	pc.weapon_type = slashing; pc.defense_type = slashing; pc.reel_count = 2
	var ps: Stats = Stats.new(); ps.focus = 4
	pc.base_stats = ps
	var built_caster: Combatant = pc.build_combatant(true)
	_check(built_caster.power_stat == &"focus", "caster combatant's power_stat is focus (got %s)" % built_caster.power_stat)
	_check(built_caster.effective_power_stat_value() == 4, "effective_power_stat_value reads Focus 4 off effective_stats (got %d)" % built_caster.effective_power_stat_value())

	print(("CHARACTER CLASS TEST PASSED" if _failures == 0 else "CHARACTER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
