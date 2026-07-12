extends SceneTree

# Headless test: InventoryDemoSetup.seed_demo_party() produces a sane placeholder party/bag/vault
# for the equipment/inventory/banking UI demo (spec 2026-07-10-equipment-inventory-banking-ui-design.md §4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_demo_setup.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()

	var pc: Combatant = party_seed["pc"]
	var companions: Array = party_seed["companions"]
	var inv: PartyInventory = party_seed["party_inventory"]
	var vault: Vault = party_seed["vault"]

	_check(pc != null, "seeds a PC Combatant")
	_check(companions.size() == 1 and companions[0] != null, "seeds exactly one companion")
	_check(inv != null and vault != null, "seeds a PartyInventory and a Vault")

	# Pre-equipped items so unequip is immediately testable (spec §4), not just equip-into-empty.
	_check(pc.gear.size() > 0, "PC starts with at least one item pre-equipped")
	_check(companions[0].gear.size() > 0, "the companion starts with at least one item pre-equipped")

	# Enough placeholder Gear/Weapon variety to exercise the level-gate: PC can equip up to its
	# level; the companion is a LOWER level so at least one bag item should be beyond its reach.
	_check(pc.level > companions[0].level, "PC is a higher level than the companion (exercises the level-gate differently per column)")
	var bag_has_rejectable_for_companion: bool = false
	for g: Gear in inv.gear:
		if not companions[0].can_equip(g):
			bag_has_rejectable_for_companion = true
			break
	_check(bag_has_rejectable_for_companion, "at least one bag item the companion's level can't equip yet")

	_check(inv.gear.size() >= 2, "the bag is seeded with multiple Gear items")
	_check(inv.weapons.size() >= 1, "the bag is seeded with at least one spare Weapon")
	_check(vault.capacity_for(&"gear") > 0, "the Vault's gear tab has some starting capacity")

	# Regression (player-reported, 2026-07-12): the bag's spare weapon must have real action reels.
	# Equipping a reel-less placeholder weapon (displacing a class-native one that DOES have reels)
	# left that combatant with a real, non-null weapon but zero attack reels — a different bug from
	# Combatant.unequip_weapon()'s null-fallback fix earlier the same day.
	for w: Weapon in inv.weapons:
		_check(w.reels.size() > 0, "bag weapon '%s' has real action reels, not an empty reel list" % w.display_name)

	# Both PC and companion start with real, non-empty weapons (their class-native ones) — and
	# equipping the bag's spare weapon onto either must not leave them reel-less either.
	_check(pc.weapon != null and pc.weapon.reels.size() > 0, "PC starts with a real weapon that has action reels")
	_check(companions[0].weapon != null and companions[0].weapon.reels.size() > 0, "the companion starts with a real weapon that has action reels")
	var spare: Weapon = inv.weapons[0]
	var displaced: Weapon = pc.equip_weapon(spare)
	_check(pc.weapon.reels.size() > 0, "equipping the bag's spare weapon onto the PC still leaves real action reels")
	_check(displaced != null and displaced.reels.size() > 0, "the displaced (original) weapon still has its own action reels, ready to re-equip")

	print(("INVENTORY DEMO SETUP TEST PASSED" if _failures == 0 else "INVENTORY DEMO SETUP TEST FAILED: %d" % _failures))
	quit(_failures)
