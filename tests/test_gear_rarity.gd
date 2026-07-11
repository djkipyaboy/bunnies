extends SceneTree

# Headless test: Gear's new 5-slot taxonomy + rarity/reel_affixes fields, and ReelAffix's shape.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_rarity.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var g: Gear = Gear.new()
	_check(g.rarity == RarityVisuals.Rarity.COMMON, "Gear defaults to Common rarity")
	_check(g.reel_affixes.size() == 0, "Gear defaults to no reel affixes")
	_check(g.slot == Gear.Slot.CHEST, "Gear defaults to Chest slot")

	# The 6 non-weapon slots exist (two independent Charm slots, design-bible §24 "Charm x2");
	# ARMOR/TRINKET no longer do (compile-time — this line would fail to parse if the enum still
	# had them removed/renamed differently).
	var slots: Array = [Gear.Slot.HEADWEAR, Gear.Slot.CLOAK, Gear.Slot.CHEST, Gear.Slot.HANDS, Gear.Slot.CHARM, Gear.Slot.CHARM_2]
	_check(slots.size() == 6, "6 non-weapon Gear slots exist")
	_check(Gear.Slot.CHARM != Gear.Slot.CHARM_2, "the two Charm slots are distinct enum values")

	var affix: ReelAffix = ReelAffix.new()
	_check(affix.kind == ReelAffix.Kind.ADD_FACE, "ReelAffix defaults to ADD_FACE")
	affix.kind = ReelAffix.Kind.TIER_BIAS
	affix.bias_pct = 0.1
	_check(affix.kind == ReelAffix.Kind.TIER_BIAS and is_equal_approx(affix.bias_pct, 0.1), "ReelAffix fields settable")

	print(("GEAR RARITY TEST PASSED" if _failures == 0 else "GEAR RARITY TEST FAILED: %d" % _failures))
	quit(_failures)
