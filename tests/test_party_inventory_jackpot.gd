extends SceneTree

# Headless test: PartyInventory.jackpot_meter's pure fill/cap/checkpoint-rounddown math
# (2026-07-29 UTIL-reel jackpot spec §2, §9). No scene/combat involved — pure Resource logic.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_party_inventory_jackpot.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(inv.jackpot_meter == 0, "jackpot_meter starts at 0")
	_check(PartyInventory.JACKPOT_CAP == 100, "JACKPOT_CAP is 100 (got %d)" % PartyInventory.JACKPOT_CAP)
	_check(PartyInventory.JACKPOT_PER_UTIL_FACE == 5, "JACKPOT_PER_UTIL_FACE is 5 (got %d)" % PartyInventory.JACKPOT_PER_UTIL_FACE)
	_check(PartyInventory.JACKPOT_PER_UTIL_PAYLINE == 15, "JACKPOT_PER_UTIL_PAYLINE is 15 (got %d)" % PartyInventory.JACKPOT_PER_UTIL_PAYLINE)

	# --- gain_jackpot() ---
	inv.gain_jackpot(5)
	_check(inv.jackpot_meter == 5, "gain_jackpot adds the flat amount (got %d)" % inv.jackpot_meter)
	inv.gain_jackpot(15)
	_check(inv.jackpot_meter == 20, "gain_jackpot accumulates (got %d)" % inv.jackpot_meter)
	inv.jackpot_meter = 97
	inv.gain_jackpot(15)
	_check(inv.jackpot_meter == 100, "gain_jackpot clamps at the cap (97+15 -> 100, got %d)" % inv.jackpot_meter)

	# --- round_down_jackpot_to_checkpoint() ---
	var i92: PartyInventory = PartyInventory.new()
	i92.jackpot_meter = 92
	i92.round_down_jackpot_to_checkpoint()
	_check(i92.jackpot_meter == 90, "92 -> 90 (got %d)" % i92.jackpot_meter)

	var i59: PartyInventory = PartyInventory.new()
	i59.jackpot_meter = 59
	i59.round_down_jackpot_to_checkpoint()
	_check(i59.jackpot_meter == 30, "59 -> 30 (got %d)" % i59.jackpot_meter)

	var i15: PartyInventory = PartyInventory.new()
	i15.jackpot_meter = 15
	i15.round_down_jackpot_to_checkpoint()
	_check(i15.jackpot_meter == 0, "below 30 rounds to 0 (15 -> 0, got %d)" % i15.jackpot_meter)

	var i30: PartyInventory = PartyInventory.new()
	i30.jackpot_meter = 30
	i30.round_down_jackpot_to_checkpoint()
	_check(i30.jackpot_meter == 30, "exactly 30 is unchanged (got %d)" % i30.jackpot_meter)

	var i60: PartyInventory = PartyInventory.new()
	i60.jackpot_meter = 60
	i60.round_down_jackpot_to_checkpoint()
	_check(i60.jackpot_meter == 60, "exactly 60 is unchanged (got %d)" % i60.jackpot_meter)

	var i90: PartyInventory = PartyInventory.new()
	i90.jackpot_meter = 90
	i90.round_down_jackpot_to_checkpoint()
	_check(i90.jackpot_meter == 90, "exactly 90 is unchanged (got %d)" % i90.jackpot_meter)

	var i100: PartyInventory = PartyInventory.new()
	i100.jackpot_meter = PartyInventory.JACKPOT_CAP
	i100.round_down_jackpot_to_checkpoint()
	_check(i100.jackpot_meter == PartyInventory.JACKPOT_CAP, "a full meter (JACKPOT_CAP) is preserved, not knocked down to 90 (got %d)" % i100.jackpot_meter)

	var i0: PartyInventory = PartyInventory.new()
	i0.round_down_jackpot_to_checkpoint()
	_check(i0.jackpot_meter == 0, "0 stays 0")

	print(("PARTY INVENTORY JACKPOT TEST PASSED" if _failures == 0 else "PARTY INVENTORY JACKPOT TEST FAILED: %d" % _failures))
	quit(_failures)
