extends SceneTree

# Headless test: weapon empowerment layer — level-derived damage scaling, neutral at level 1,
# recomputed live from Combatant.level (not a persisted "weapon level").
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_weapon_empowerment.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	w.rarity = RarityVisuals.Rarity.LEGENDARY   # authored affix budget — untouched by level

	var c: Combatant = Combatant.new()
	c.weapon = w

	# Level 1 (the default for every existing combatant): exactly neutral, no bonus.
	_check(c.level == 1, "Combatant defaults to level 1")
	_check(is_equal_approx(c.weapon_effective_base_damage(), 10.0), "level 1 -> no empowerment bonus (got %f)" % c.weapon_effective_base_damage())

	# Level 9: +3%/level for 8 levels above 1 = +24%.
	c.level = 9
	_check(is_equal_approx(c.weapon_effective_base_damage(), 12.4), "level 9 -> 10 * 1.24 = 12.4 (got %f)" % c.weapon_effective_base_damage())

	# Instant rescale: dropping level back down rescales down immediately (no persisted state).
	c.level = 1
	_check(is_equal_approx(c.weapon_effective_base_damage(), 10.0), "rescales back down instantly on level change")

	# A weapon's own rarity (affix budget) is untouched by level — it's a separate concern from the
	# level-derived damage/tier display (spec §3.4).
	_check(w.rarity == RarityVisuals.Rarity.LEGENDARY, "authored weapon rarity unaffected by level")
	_check(RarityVisuals.rarity_for_level(9) == RarityVisuals.Rarity.LEGENDARY, "displayed tier at level 9 is Legendary")
	_check(RarityVisuals.rarity_for_level(1) == RarityVisuals.Rarity.COMMON, "displayed tier at level 1 is Common (independent of the Legendary weapon's own affixes)")

	# No weapon equipped -> 0, not a crash.
	var bare: Combatant = Combatant.new()
	_check(bare.weapon_effective_base_damage() == 0.0, "no weapon -> 0.0")

	print(("WEAPON EMPOWERMENT TEST PASSED" if _failures == 0 else "WEAPON EMPOWERMENT TEST FAILED: %d" % _failures))
	quit(_failures)
