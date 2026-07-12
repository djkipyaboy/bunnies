extends SceneTree

# Headless test: Combatant.equip_gear/unequip_gear/equip_weapon/unequip_weapon (spec
# 2026-07-10-equipment-inventory-banking-ui-design.md §2.1).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_equip_unequip.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.level = 9
	c.base_stats = Stats.new()

	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.stat_bonuses = Stats.new()

	var displaced: Gear = c.equip_gear(hat)
	_check(displaced == null, "equipping into an empty slot displaces nothing")
	_check(c.gear.has(hat), "equipped gear is in Combatant.gear")

	var hat2: Gear = Gear.new()
	hat2.slot = Gear.Slot.HEADWEAR
	hat2.stat_bonuses = Stats.new()
	var displaced2: Gear = c.equip_gear(hat2)
	_check(displaced2 == hat, "equipping into an occupied slot displaces the previous item")
	_check(c.gear.has(hat2) and not c.gear.has(hat), "gear array now holds only the new item in that slot")

	var unequipped: Gear = c.unequip_gear(Gear.Slot.HEADWEAR)
	_check(unequipped == hat2, "unequip_gear returns the removed item")
	_check(not c.gear.has(hat2), "unequip_gear removes it from Combatant.gear")
	_check(c.unequip_gear(Gear.Slot.HEADWEAR) == null, "unequipping an empty slot returns null")

	# A rejected equip (level-gate) changes nothing and returns null.
	var rare: Gear = Gear.new()
	rare.slot = Gear.Slot.CHEST
	rare.rarity = RarityVisuals.Rarity.RARE
	rare.stat_bonuses = Stats.new()
	c.level = 1
	_check(c.equip_gear(rare) == null, "a rejected equip (level-gate) returns null")
	_check(not c.gear.has(rare), "a rejected equip changes nothing")

	# The two Charm slots are independent — equipping into CHARM_2 must not displace CHARM.
	c.level = 9
	var charm1: Gear = Gear.new()
	charm1.slot = Gear.Slot.CHARM
	charm1.stat_bonuses = Stats.new()
	var charm2: Gear = Gear.new()
	charm2.slot = Gear.Slot.CHARM_2
	charm2.stat_bonuses = Stats.new()
	_check(c.equip_gear(charm1) == null, "equipping into CHARM displaces nothing")
	_check(c.equip_gear(charm2) == null, "equipping into CHARM_2 does not displace CHARM")
	_check(c.gear.has(charm1) and c.gear.has(charm2), "both Charm slots hold their own item simultaneously")

	# Weapon straight-swap.
	var w1: Weapon = Weapon.new()
	var w2: Weapon = Weapon.new()
	_check(c.equip_weapon(w1) == null, "equip_weapon with nothing equipped returns null")
	_check(c.weapon == w1, "equip_weapon sets Combatant.weapon")
	_check(c.equip_weapon(w2) == w1, "equip_weapon returns the previous weapon")
	_check(c.weapon == w2, "equip_weapon replaces Combatant.weapon")
	_check(c.unequip_weapon() == w2, "unequip_weapon returns the removed weapon")

	# Unarmed fallback (player-reported gap, 2026-07-12): unequip_weapon() never actually leaves
	# Combatant.weapon null — it falls back to a real 2-reel Unarmed Strike, so a disarmed combatant
	# still has action reels instead of zero.
	_check(c.weapon != null, "unequip_weapon leaves a real (unarmed) weapon, not null")
	_check(c.weapon.is_unarmed, "the fallback weapon is flagged is_unarmed")
	_check(c.weapon.reels.size() == 2, "the unarmed fallback has 2 action reels")
	_check(c.unequip_weapon() == null, "unequipping an already-unarmed combatant returns null (the unarmed placeholder itself is never treated as a real displaced item)")
	_check(c.weapon.is_unarmed, "still unarmed (a fresh unarmed weapon, not the same instance, but still flagged) after a second unequip")

	print(("GEAR EQUIP/UNEQUIP TEST PASSED" if _failures == 0 else "GEAR EQUIP/UNEQUIP TEST FAILED: %d" % _failures))
	quit(_failures)
