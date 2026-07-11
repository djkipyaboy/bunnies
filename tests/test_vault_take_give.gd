extends SceneTree

# Headless test: Vault.take_gear/give_gear/take_weapon/give_weapon — bag-side, uncapped,
# no-boundary-crossing methods mirroring PartyInventory's, added so a later task can swap an
# item directly out of the Vault (equip-from-vault) without capacity bookkeeping.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_vault_take_give.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var vault: Vault = Vault.new()

	var g1: Gear = Gear.new()
	g1.slot = Gear.Slot.HEADWEAR
	g1.stat_bonuses = Stats.new()

	vault.give_gear(g1)
	_check(vault.gear.has(g1), "give_gear adds the item to vault.gear")

	vault.take_gear(g1)
	_check(not vault.gear.has(g1), "take_gear removes the item from vault.gear")
	_check(vault.gear.size() == 0, "vault.gear is empty after take_gear")

	var w1: Weapon = Weapon.new()
	vault.give_weapon(w1)
	_check(vault.weapons.has(w1), "give_weapon adds the item to vault.weapons")

	vault.take_weapon(w1)
	_check(not vault.weapons.has(w1), "take_weapon removes the item from vault.weapons")
	_check(vault.weapons.size() == 0, "vault.weapons is empty after take_weapon")

	# Equip-from-vault swap simulation: take the currently-equipped item out, give back the
	# previously-worn item — a net-zero round trip that never touches capacity.
	var g_old: Gear = Gear.new()
	g_old.slot = Gear.Slot.CHEST
	g_old.stat_bonuses = Stats.new()
	var g_new: Gear = Gear.new()
	g_new.slot = Gear.Slot.CHEST
	g_new.stat_bonuses = Stats.new()

	vault.give_gear(g_new)  # g_new starts in the vault, about to be equipped
	_check(vault.gear.has(g_new), "swap setup: vault holds the incoming item")

	vault.take_gear(g_new)      # equip pulls g_new out of the vault
	vault.give_gear(g_old)      # the previously-equipped g_old is deposited back in its place
	_check(not vault.gear.has(g_new), "swap: the newly-equipped item is no longer in the vault")
	_check(vault.gear.has(g_old), "swap: the displaced item is now in the vault")
	_check(vault.gear.size() == 1, "swap: vault.gear holds exactly the displaced item (net-zero)")

	var w_old: Weapon = Weapon.new()
	var w_new: Weapon = Weapon.new()
	vault.give_weapon(w_new)
	vault.take_weapon(w_new)
	vault.give_weapon(w_old)
	_check(not vault.weapons.has(w_new), "weapon swap: the newly-equipped weapon is no longer in the vault")
	_check(vault.weapons.has(w_old), "weapon swap: the displaced weapon is now in the vault")
	_check(vault.weapons.size() == 1, "weapon swap: vault.weapons holds exactly the displaced weapon (net-zero)")

	print(("VAULT TAKE/GIVE TEST PASSED" if _failures == 0 else "VAULT TAKE/GIVE TEST FAILED: %d" % _failures))
	quit(_failures)
