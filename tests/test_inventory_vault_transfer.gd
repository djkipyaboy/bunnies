extends SceneTree

# Headless test: PartyInventory<->Vault gear/weapon transfer (spec
# 2026-07-10-equipment-inventory-banking-ui-design.md §2.2).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_vault_transfer.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	vault.tab_capacity[&"gear"] = 1
	vault.tab_capacity[&"weapons"] = 1

	var g: Gear = Gear.new()
	inv.gear = [g]
	_check(vault.deposit_gear(g, inv), "deposit_gear succeeds under capacity")
	_check(not inv.gear.has(g), "deposit_gear removes the item from the bag")
	_check(vault.gear.has(g), "deposit_gear adds the item to the Vault")

	var g2: Gear = Gear.new()
	inv.gear = [g2]
	_check(not vault.deposit_gear(g2, inv), "deposit_gear blocked when the gear tab is at capacity")
	_check(inv.gear.has(g2), "a blocked deposit leaves the bag untouched")
	_check(not vault.gear.has(g2), "a blocked deposit leaves the Vault untouched")

	vault.withdraw_gear(g, inv)
	_check(not vault.gear.has(g), "withdraw_gear removes the item from the Vault")
	_check(inv.gear.has(g), "withdraw_gear returns the item to the bag")

	var w: Weapon = Weapon.new()
	inv.weapons = [w]
	_check(vault.deposit_weapon(w, inv), "deposit_weapon succeeds under capacity")
	_check(not inv.weapons.has(w), "deposit_weapon removes the weapon from the bag")
	_check(vault.weapons.has(w), "deposit_weapon adds the weapon to the Vault")

	var w2: Weapon = Weapon.new()
	inv.weapons = [w2]
	_check(not vault.deposit_weapon(w2, inv), "deposit_weapon blocked at the weapons-tab capacity")

	vault.withdraw_weapon(w, inv)
	_check(not vault.weapons.has(w), "withdraw_weapon removes the weapon from the Vault")
	_check(inv.weapons.has(w), "withdraw_weapon returns the weapon to the bag")

	# Bag-side take/give never capacity-check.
	for i in range(50):
		inv.give_gear(Gear.new())
	_check(inv.gear.size() > 40, "PartyInventory.give_gear never capacity-checks")

	print(("INVENTORY/VAULT TRANSFER TEST PASSED" if _failures == 0 else "INVENTORY/VAULT TRANSFER TEST FAILED: %d" % _failures))
	quit(_failures)
