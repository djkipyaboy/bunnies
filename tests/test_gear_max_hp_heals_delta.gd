extends SceneTree

## Headless test for the 2026-07-23 playtest bug fix: equipping gear that raises max HP must shift
## current HP by the same delta (preserving the MISSING HP amount), not silently leave HP unchanged
## (e.g. 301/304 instead of 304/304). Symmetric on unequip, and only applies to a combatant already
## alive (hp > 0) so initial character setup before start_combat() is unaffected.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.level = 1
	c.base_stats = Stats.new()
	c.base_max_hp = 301
	c.apply_stats()
	c.start_combat()
	_check(c.max_hp == 301 and c.hp == 301, "starts full at the base max HP")

	var vest: Gear = Gear.new()
	vest.slot = Gear.Slot.CHEST
	vest.stat_bonuses = Stats.new()
	vest.stat_bonuses.vigor = 3

	c.equip_gear(vest)
	_check(c.max_hp == 304, "max HP rises by the gear's Vigor bonus")
	_check(c.hp == 304, "full-health character is healed for the exact delta, staying full (was the reported 301/304 bug)")

	# Take some damage, THEN equip more Vigor — the MISSING HP amount (not the raw HP number) must
	# be preserved.
	c.take_damage(9)
	_check(c.hp == 295, "sanity: took 9 damage")
	var charm: Gear = Gear.new()
	charm.slot = Gear.Slot.CHARM
	charm.stat_bonuses = Stats.new()
	charm.stat_bonuses.vigor = 6
	c.equip_gear(charm)
	_check(c.max_hp == 310, "max HP rises again by the second item's Vigor")
	_check(c.hp == 301, "HP rises by the same +6 delta, preserving the 9-missing-HP gap (295 -> 301, not stuck at 295)")

	# Unequipping is symmetric — losing Vigor shifts HP back down by the same delta.
	c.unequip_gear(Gear.Slot.CHARM)
	_check(c.max_hp == 304, "max HP falls back after unequip")
	_check(c.hp == 295, "HP falls by the same delta, restoring the original 9-missing-HP gap")

	# A combatant not yet alive (hp == 0, pre-start_combat()) is unaffected — equip-time gearing
	# during setup must never resurrect/half-fill anyone.
	var fresh: Combatant = Combatant.new()
	fresh.level = 1
	fresh.base_stats = Stats.new()
	fresh.base_max_hp = 100
	var boots: Gear = Gear.new()
	boots.slot = Gear.Slot.HANDS
	boots.stat_bonuses = Stats.new()
	boots.stat_bonuses.vigor = 5
	fresh.equip_gear(boots)
	_check(fresh.hp == 0, "a not-yet-started combatant's hp stays 0 through setup-time gearing")
	_check(fresh.max_hp == 105, "its max HP still reflects the gear normally")

	print(("GEAR MAX-HP HEALS DELTA TEST PASSED" if _failures == 0 else "GEAR MAX-HP HEALS DELTA TEST FAILED: %d" % _failures))
	quit(_failures)
