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
	var s: Stats = Stats.new(); s.might = 3; s.vigor = 3; s.focus = 1; s.grit = 2; s.luck = 1
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

	var c: Combatant = cc.build_combatant(true)
	_check(c.display_name == "Test Warrior", "display_name copied")
	_check(c.is_player == true, "is_player set")
	_check(c.weapon != null and c.weapon.reels.size() == 3, "weapon has reel_count=3 reels (got %d)" % (c.weapon.reels.size() if c.weapon else -1))
	_check(c.weapon.base_damage == 8.0, "weapon base_damage copied")
	_check(c.defense_type == slashing, "defense_type set")
	_check(c.ability_id == &"rend", "ability_id set")
	# Derived: max_hp = base 100 + vigor 3 = 103; max_stamina = base 5 + focus 1 = 6; floor = 3 + grit 2 = 5.
	_check(c.max_hp == 103, "max_hp = 100 + vigor 3 = 103 (got %d)" % c.max_hp)
	_check(c.resource_pool != null and c.resource_pool.max_stamina == 6, "max_stamina = 5 + focus 1 = 6 (got %d)" % (c.resource_pool.max_stamina if c.resource_pool else -1))
	_check(c.bonus_meter != null and c.bonus_meter.floor == 5, "meter floor = 3 + grit 2 = 5 (got %d)" % (c.bonus_meter.floor if c.bonus_meter else -1))
	_check(c.bonus_meter.cap == 15, "meter cap copied")
	_check(c.hp == c.max_hp, "start_combat seeded full HP")
	# Luck 1 added 1 crit face per reel.
	var crit: int = 0
	for f: ReelFace in c.weapon.reels[0].faces:
		if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS: crit += 1
	_check(crit == 2, "apply_luck added 1 crit face (1 default + 1 = 2; got %d)" % crit)

	# Enemy build: no meter visibility, no stamina pool.
	var ec: CharacterClass = CharacterClass.new()
	ec.weapon_type = slashing; ec.defense_type = slashing; ec.reel_count = 2
	var e: Combatant = ec.build_combatant(false)
	_check(e.bonus_meter != null and e.bonus_meter.is_visible == false, "enemy meter hidden")
	_check(e.resource_pool == null, "enemy has no stamina pool")

	print(("CHARACTER CLASS TEST PASSED" if _failures == 0 else "CHARACTER CLASS TEST FAILED: %d" % _failures))
	quit(_failures)
