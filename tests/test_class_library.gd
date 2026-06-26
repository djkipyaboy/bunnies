extends SceneTree

# Headless test: the three v1 classes match the design spec (§2 roster, §3 stats, §4A abilities).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var warrior: CharacterClass = ClassLibrary.make(&"warrior")
	_check(warrior != null, "warrior exists")
	_check(warrior.reel_count == 3 and warrior.base_stats.might == 3, "warrior: 3 reels, Might 3")
	_check(warrior.ability_id == &"rend", "warrior ability = rend")
	_check(warrior.display_name == "Martin (Mouse)", "warrior is Martin")
	_check(warrior.weapon_base_damage == 8.0, "warrior sword base 8")

	_check(warrior.ultimate_id == &"wild", "warrior ultimate = wild (single-spin)")

	var vanguard: CharacterClass = ClassLibrary.make(&"vanguard")
	_check(vanguard.reel_count == 2 and vanguard.base_stats.vigor == 5, "vanguard: 2 reels, Vigor 5")
	_check(vanguard.ability_id == &"heft", "vanguard ability = heft")
	_check(vanguard.ultimate_id == &"rampage", "vanguard ultimate = rampage (+1 reel, Heft-all, AoE)")
	_check(vanguard.base_stats.grit == 3, "vanguard high Grit 3 (meter carryover)")
	_check(vanguard.weapon_base_damage == 15.0, "vanguard maul base 15")

	var skirmisher: CharacterClass = ClassLibrary.make(&"skirmisher")
	_check(skirmisher.reel_count == 4 and skirmisher.base_stats.finesse == 5, "skirmisher: 4 reels (dual-wield), Finesse 5")
	_check(skirmisher.ability_id == &"flurry", "skirmisher ability = flurry")
	_check(skirmisher.weapon_base_damage == 6.0, "skirmisher sabre base 6")
	_check(skirmisher.meter_cap == 30, "skirmisher meter_cap 30 (raised — charges fast)")
	_check(skirmisher.ultimate_id == &"sticky_wild", "skirmisher ultimate = sticky_wild (2-spin)")

	var ranger: CharacterClass = ClassLibrary.make(&"ranger")
	_check(ranger.reel_count == 4 and ranger.base_stats.finesse == 4, "ranger: 4 reels, Finesse 4")
	_check(ranger.ability_id == &"hunters_mark", "ranger ability = hunters_mark")
	_check(ranger.ability_cost == 3 and ranger.ability_resource == &"stamina", "hunters_mark costs 3 stamina")
	_check(ranger.ultimate_id == &"collateral", "ranger ultimate = collateral")
	_check(ranger.weapon_base_damage == 7.0, "ranger bow base 7")

	_check(ClassLibrary.make(&"nope") == null, "unknown id -> null")
	_check(ClassLibrary.IDS.size() == 5, "5 classes registered (+ Ranger)")

	# Each class builds a valid combatant end-to-end.
	for id: StringName in ClassLibrary.IDS:
		var c: Combatant = ClassLibrary.make(id).build_combatant(true)
		_check(c.is_alive() and c.weapon.reels.size() >= 2, "%s builds a live combatant" % id)

	# Vanguard charges +2 on NEUTRAL (index 2); Warrior/Skirmisher keep the default +1.
	var van: Combatant = ClassLibrary.make(&"vanguard").build_combatant(true)
	_check(van.bonus_meter.charge_weights[ReelFace.ResultTier.NEUTRAL] == 2, "vanguard neutral meter gain = 2 (got %d)" % van.bonus_meter.charge_weights[ReelFace.ResultTier.NEUTRAL])
	var war: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	_check(war.bonus_meter.charge_weights[ReelFace.ResultTier.NEUTRAL] == 1, "warrior neutral meter gain = 1 (default, got %d)" % war.bonus_meter.charge_weights[ReelFace.ResultTier.NEUTRAL])

	print(("CLASS LIBRARY TEST PASSED" if _failures == 0 else "CLASS LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
